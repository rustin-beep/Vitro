// #517 P3-14（C7，2026-11-14）：未初始化局部标量读取的静态警告——
// clang -Wuninitialized 的**保守子集**（简化数据流，漏报方向安全、零误报
// 优先）。实拍缺口：`int u; int v = u + 1;` 零警告（clang 有警告）——
// Vitro 确定性零初始化（u=0）让学生看不到「忘了初始化」这件事本身。
//
// 语义边界（设计拍板，均登记）：
// - 只查函数内声明的**标量**（整族/浮族/char/指针——含 unsigned 变体）；
//   数组/struct/union 跳过（元素/成员级追踪需真实数据流，超出保守子集）；
// - 赋值/复合赋值/自增自减 → 视为已初始化（`u += 1`/`u++` 的读侧按写
//   处理——漏报方向安全）；取址 `&u`（含出现在调用实参中）→ 视为已
//   初始化（scanf 写入是教学主场景，&a[i] 数组形态本就不追踪）；
// - if 带双分支且**两侧都赋值** → 传播（快照交集）；单分支/循环体/
//   switch 体内在赋值不传播（漏报方向）；
// - 全局/静态不查（C 保证零初始化）；函数参数不查（调用方已传值）；
// - 同名 shadow 按名合并（保守子集不建作用域映射）；每名至多一次警告
//   （首次读取点），警告后不再重复报。

///|
/// 追踪状态：未初始化且未警告的标量局部（name → 声明 loc）+ 已警告名集
/// + 错误行集（错误恢复期的声明不追踪）。
priv struct UninitState {
  mut pending : Map[String, @source.SourceLoc]
  warned : Set[String]
  error_lines : Set[Int32]
}

///|
/// 标量判定（追踪面）：整族/浮族/char/long long/指针；数组/struct/
/// union/void/函数指针以外全收。#517 CI 连坐修正（2026-11-14）：函数
/// 原型声明（体内 `int f();`）以函数指针形态进 VarDecl——追踪它会在
/// 后续调用点把**函数名**误报为未初始化读取（kr_2_8 实锤）；pointee
/// 链含 Function 一律不收（函数指针未初始化调用属罕见形态，漏报方向安全）。
fn uninit_trackable(ty : @ast.Type) -> Bool {
  match ty.kind() {
    TK_Int | TK_Char | TK_Float | TK_Double | TK_LongLong => true
    TK_Pointer => !uninit_pointee_is_function(ty)
    _ => false
  }
}

///|
/// pointee 链是否含函数类型（函数指针/函数原型形态）。
fn uninit_pointee_is_function(ty : @ast.Type) -> Bool {
  match ty {
    Pointer(pointee, _) =>
      match pointee.kind() {
        TK_Function => true
        TK_Pointer => uninit_pointee_is_function(pointee)
        _ => false
      }
    _ => false
  }
}

///|
/// 入口：函数体顶层（挂点 = check_function 尾段，W3084 同点）。
/// param_names：**函数形参名集**——KNR 风格定义的参数声明（`int f(a, b)
/// int a; int b; {...}`）在函数体内以 VarDecl 无初始化形态出现、与参数
/// 同名——按参数处理不追踪（调用方已传值；kr_5_8/kr_5_14 实锤）。
/// error_lines：本遍历前已报 error 的行集——**错误恢复期造出的声明不
/// 追踪**（局部 `extern int x;` 在 C 子集不支持、报 E2003 后恢复出的
/// VarDecl 上叠 W3099 是级联噪声；chibicc extern.c 实锤）。
fn TypeChecker::check_uninitialized_reads(
  self : TypeChecker,
  func_name : String,
  param_names : Array[String],
  body : @ast.Stmt,
) -> Unit {
  ignore(func_name)
  let st : UninitState = {
    pending: Map([]),
    warned: Set([]),
    error_lines: Set([]),
  }
  for p in param_names {
    st.warned.add(p)
  }
  for e in self.errors {
    st.error_lines.add(e.line)
  }
  self.uninit_walk_stmt(body, st)
}

///|
fn TypeChecker::uninit_walk_stmt(
  self : TypeChecker,
  stmt : @ast.Stmt,
  st : UninitState,
) -> Unit {
  match stmt {
    Block(ss, _) =>
      for s in ss {
        self.uninit_walk_stmt(s, st)
      }
    VarDecl(ty, name, init, extras, is_static, _, loc) => {
      // #517 CI 连坐修正：挂点在函数作用域出栈后——lookup_var 只会命中
      // 文件作用域符号；局部 `extern int ext3;` 声明（引用外部定义，非
      // 未初始化局部）与「局部 shadow 全局同名」一并不追踪（后者漏报
      // 方向安全；extern.c 实锤）
      if !is_static &&
        uninit_trackable(ty) &&
        init is None &&
        self.lookup_var(name) is None &&
        !st.error_lines.contains(loc.line) {
        if !st.pending.contains(name) {
          st.pending.set(name, loc)
        }
      }
      for ex in extras {
        if !is_static &&
          uninit_trackable(ex.var_type) &&
          ex.init is None &&
          self.lookup_var(ex.name) is None &&
          !st.error_lines.contains(loc.line) {
          if !st.pending.contains(ex.name) {
            st.pending.set(ex.name, loc)
          }
        }
        match ex.init {
          Some(e) => self.uninit_track_expr(e, st)
          None => ()
        }
      }
      match init {
        Some(e) => self.uninit_track_expr(e, st)
        None => ()
      }
    }
    Expr(e, _) => self.uninit_track_expr(e, st)
    If(cond, then_s, else_s, _) => {
      self.uninit_walk_expr(cond, st)
      match else_s {
        Some(el) => {
          // 双分支：两侧快照分别扫，两侧都赋值（都从 pending 消失）才传播
          let snap = st.pending.copy()
          self.uninit_walk_stmt(then_s, st)
          let after_then = st.pending.copy()
          st.pending = snap.copy()
          self.uninit_walk_stmt(el, st)
          let after_else = st.pending
          // 交集传播：snap 里有、两侧都移除的保持移除；任一侧仍在则恢复
          let restored : Map[String, @source.SourceLoc] = Map([])
          for name, l in after_else {
            if after_then.contains(name) && snap.contains(name) {
              restored.set(name, l)
            }
          }
          st.pending = restored
        }
        None => {
          // 单分支：体内赋值不传播（快照恢复——漏报方向安全）
          let snap = st.pending.copy()
          self.uninit_walk_stmt(then_s, st)
          st.pending = snap
        }
      }
    }
    While(cond, body_s, _) => {
      self.uninit_walk_expr(cond, st)
      let snap = st.pending.copy()
      self.uninit_walk_stmt(body_s, st)
      st.pending = snap
    }
    DoWhile(body_s, cond, _) => {
      let snap = st.pending.copy()
      self.uninit_walk_stmt(body_s, st)
      st.pending = snap
      self.uninit_walk_expr(cond, st)
    }
    For(init_s, cond, steps, body_s, _) => {
      match init_s {
        Some(s) => self.uninit_walk_stmt(s, st)
        None => ()
      }
      match cond {
        Some(c) => self.uninit_walk_expr(c, st)
        None => ()
      }
      let snap = st.pending.copy()
      for s in steps {
        self.uninit_track_expr(s, st)
      }
      self.uninit_walk_stmt(body_s, st)
      st.pending = snap
    }
    Return(e, _) =>
      match e {
        Some(x) => self.uninit_walk_expr(x, st)
        None => ()
      }
    // switch/case 穿越：线性透传（case 内赋值传播 = 漏报方向安全）
    Switch(cond, body_s, _) => {
      self.uninit_walk_expr(cond, st)
      self.uninit_walk_stmt(body_s, st)
    }
    Case(_, body_s, _) => self.uninit_walk_stmt(body_s, st)
    Label(_, body_s, _) => self.uninit_walk_stmt(body_s, st)
    Break(_) | Continue(_) | Goto(_, _) => ()
    // C++ 专属（C 输入不可达——穷尽 match 纪律，语义对齐：RangeFor 的
    // 循环变量带初始化天然已初始化；Try 三段照走）
    RangeFor(loop_var, _, iter, body_s, _) => {
      ignore(loop_var)
      self.uninit_walk_expr(iter, st)
      self.uninit_walk_stmt(body_s, st)
    }
    Try(body_s, _, _) => self.uninit_walk_stmt(body_s, st)
  }
}

///|
/// 表达式语句级：赋值的 LHS 是写（其余子树照读侧走）。
fn TypeChecker::uninit_track_expr(
  self : TypeChecker,
  e : @ast.Expr,
  st : UninitState,
) -> Unit {
  match e {
    Assign(_, lhs, rhs, _, _) => {
      self.uninit_walk_expr(rhs, st)
      match lhs {
        Identifier(name, _, _) =>
          // 写侧：复合赋值/自增自减的读侧并入写处理（漏报方向安全）
          ignore(st.pending.remove(name))
        _ => self.uninit_walk_expr(lhs, st)
      }
    }
    _ => self.uninit_walk_expr(e, st)
  }
}

///|
/// 读侧遍历：Identifier 命中 pending 即警（一次）；取址视为初始化。
fn TypeChecker::uninit_walk_expr(
  self : TypeChecker,
  e : @ast.Expr,
  st : UninitState,
) -> Unit {
  match e {
    Identifier(name, loc, _) =>
      if st.pending.contains(name) && !st.warned.contains(name) {
        st.warned.add(name)
        ignore(st.pending.remove(name))
        self.report_warning(
          "读取了未初始化的局部变量 '\{name}'——本行读到的是初始值 0（Vitro 的教学零初始化），忘初始化可能是笔误；先赋值再使用，或用 scanf/取址方式写入",
          loc,
          W3099_UninitializedRead,
        )
      }
    Unary(op, inner, _, _) => {
      if op is @ast.UnaryOp::Addr {
        match inner {
          Identifier(name, _, _) =>
            // &u 传出（scanf 写入主场景）→ 视为已初始化
            ignore(st.pending.remove(name))
          _ => ()
        }
      }
      self.uninit_walk_expr(inner, st)
    }
    Call(_, args, _, _) =>
      for a in args {
        // 实参内嵌赋值/取址按语句级规则（&u 传参 = 写入口）
        self.uninit_track_expr(a, st)
      }
    CallPtr(f, args, _, _) => {
      // #517 CI 连坐修正：callee 不按读处理——C 输入统一在 CallPtr，
      // callee 是函数名形态（函数名被报 W3099 的第二路径；函数指针变量
      // 未初始化调用属罕见形态，漏报方向安全）
      ignore(f)
      for a in args {
        self.uninit_track_expr(a, st)
      }
    }
    Binary(_, l, r, _, _) => {
      self.uninit_walk_expr(l, st)
      self.uninit_walk_expr(r, st)
    }
    Ternary(c, t, el, _, _) => {
      self.uninit_walk_expr(c, st)
      self.uninit_walk_expr(t, st)
      self.uninit_walk_expr(el, st)
    }
    Index(b, i, _, _) => {
      self.uninit_walk_expr(b, st)
      self.uninit_walk_expr(i, st)
    }
    Member(o, _, _, _, _) => self.uninit_walk_expr(o, st)
    // (void)u 是 C 惯用的「我知道没用到」显式抑制标记——clang
    // -Wuninitialized 同款不报（#517 CI 连坐修正：chibicc 语料的
    // `(void)x;` 形态曾误报；attribute.c 实锤）
    Cast(inner, target_ty, _, _) =>
      if target_ty.kind() is TK_Void && inner is Identifier(_, _, _) {
        // 显式抑制：既不报也不视为初始化
        ()
      } else {
        self.uninit_walk_expr(inner, st)
      }
    Assign(_, _, _, _, _) => self.uninit_track_expr(e, st)
    _ => ()
  }
}
