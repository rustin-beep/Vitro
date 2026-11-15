///|
/// **批 4′ 变参 host 侧车扫描器**：typed AST → 变参路由（printf/
/// sprintf/snprintf/sscanf）调用序的实参个数（`build_dispatch_input` 的
/// `variadic_argc~` 供给面）。
///
/// **对齐契约**（与 codegen 压参序同构双保险）：
/// - 扫描序 = AST 声明序/语句序/求值序（codegen 同 visitor 序）——
///   产出与 code 里 CallHost(变参) 序按**计数 + 路由对齐**对账
///   （build_host_sites 侧车游标对账 fail loud，缺/多即 NotSupported
///   禁译不静默）；
/// - 只收**路由到 CallHost 的名字**（`@bytecode.host_route` 派生——
///   Bytecode Libc 预注册名〔printf 无预注册——恒 CallHost〕；func_index
///   遮蔽判定在 codegen call.mbt——printf 族四名无同名用户函数遮蔽形态
///   时直发 CallHost，**用户定义同名 printf 函数**时路由变 Call——本
///   扫描器按「AST 调用点名字 ∈ 四名」收集会多计，侧车对账红即拦）。
///
/// Stmt 16 / Expr 26 穷尽 match——新形态编译红连坐（编码纪律 1）。

///|
/// 变参 host 路由名（printf 族 + sscanf——`host_window_sig` argc=None 域）。
fn is_variadic_host_name(name : String) -> Bool {
  name == "printf" ||
  name == "sprintf" ||
  name == "snprintf" ||
  name == "sscanf"
}

///|
/// ProgramNode → 变参路由调用序实参个数表。
pub fn scan_variadic_host_argc(p : @ast.ProgramNode) -> Array[Int32] {
  let out : Array[Int32] = []
  // 声明序：structs/unions/globals/funcs（codegen gen_program 同序域——
  // 前三族无调用点，funcs 是唯一收集面；全局初始化表达式照走）
  for g in p.globals {
    match g.init {
      Some(e) => walk_expr(e, out)
      None => ()
    }
  }
  for f in p.funcs {
    match f.body {
      Some(b) => walk_stmt(b, out)
      None => ()
    }
  }
  out
}

///|
fn walk_stmt(s : @ast.Stmt, out : Array[Int32]) -> Unit {
  match s {
    Block(stmts, _) =>
      for x in stmts {
        walk_stmt(x, out)
      }
    VarDecl(_, _, init, extra, _, _, _) => {
      match init {
        Some(e) => walk_expr(e, out)
        None => ()
      }
      for ev in extra {
        match ev.init {
          Some(e) => walk_expr(e, out)
          None => ()
        }
      }
    }
    Expr(e, _) => walk_expr(e, out)
    If(c, t, e, _) => {
      walk_expr(c, out)
      walk_stmt(t, out)
      match e {
        Some(x) => walk_stmt(x, out)
        None => ()
      }
    }
    While(c, b, _) => {
      walk_expr(c, out)
      walk_stmt(b, out)
    }
    DoWhile(b, c, _) => {
      walk_stmt(b, out)
      walk_expr(c, out)
    }
    For(init, cond, step, b, _) => {
      match init {
        Some(x) => walk_stmt(x, out)
        None => ()
      }
      match cond {
        Some(x) => walk_expr(x, out)
        None => ()
      }
      for x in step {
        walk_expr(x, out)
      }
      walk_stmt(b, out)
    }
    Return(e, _) =>
      match e {
        Some(x) => walk_expr(x, out)
        None => ()
      }
    Break(_) => ()
    Continue(_) => ()
    Switch(c, b, _) => {
      walk_expr(c, out)
      walk_stmt(b, out)
    }
    Case(l, b, _) => {
      match l {
        Some(x) => walk_expr(x, out)
        None => ()
      }
      walk_stmt(b, out)
    }
    Goto(_, _) => ()
    Label(_, b, _) => walk_stmt(b, out)
    // === C++（C 子集零到达——防御面同构遍历）===
    RangeFor(_, _, iter, b, _) => {
      walk_expr(iter, out)
      walk_stmt(b, out)
    }
    Try(b, catches, _) => {
      walk_stmt(b, out)
      for c in catches {
        walk_stmt(c.body, out)
      }
    }
  }
}

///|
fn walk_expr(e : @ast.Expr, out : Array[Int32]) -> Unit {
  match e {
    Call(name, args, _, _) => {
      // 调用点收集（先本点后实参——codegen gen_call 先压参后 CallHost，
      // 但**调用序**以调用点计：嵌套调用（printf("%d", g(1))）的内层 g
      // 先求值——walk 实参在前更贴求值序；printf 自身嵌套
      //（printf("%d", printf(...))）时内层先——**实参先走**）
      for a in args {
        walk_expr(a, out)
      }
      if is_variadic_host_name(name) {
        out.push(args.length())
      }
    }
    CallPtr(callee, args, _, _) => {
      // **typed AST 的调用主形态**（probe 实锤）：标识符调用 lowering 后
      // 统一 CallPtr(Identifier(name))——codegen call.mbt 的 CallPtr 解析臂
      // 同源；变参 host 收集在此（Call 臂为 C++/形态防御保留）
      for a in args {
        walk_expr(a, out)
      }
      match callee {
        Identifier(name, _, _) =>
          if is_variadic_host_name(name) {
            out.push(args.length())
          }
        _ => ()
      }
      walk_expr(callee, out)
    }
    MemberCall(obj, _, args, _, _, _, _) => {
      walk_expr(obj, out)
      for a in args {
        walk_expr(a, out)
      }
    }
    Binary(_, l, r, _, _) => {
      walk_expr(l, out)
      walk_expr(r, out)
    }
    Unary(_, x, _, _) => walk_expr(x, out)
    Literal(_, _, _) => ()
    FloatLiteral(_, _, _) => ()
    LongLiteral(_, _, _) => ()
    StringLiteral(_, _, _) => ()
    Identifier(_, _, _) => ()
    Index(arr, i, _, _) => {
      walk_expr(arr, out)
      walk_expr(i, out)
    }
    Member(obj, _, _, _, _) => walk_expr(obj, out)
    Assign(_, l, r, _, _) => {
      walk_expr(l, out)
      walk_expr(r, out)
    }
    Ternary(c, t, f, _, _) => {
      walk_expr(c, out)
      walk_expr(t, out)
      walk_expr(f, out)
    }
    Sizeof(t, x, _, _) => {
      ignore(t)
      match x {
        Some(y) => walk_expr(y, out)
        None => ()
      }
    }
    Alignof(t, x, _, _) => {
      ignore(t)
      match x {
        Some(y) => walk_expr(y, out)
        None => ()
      }
    }
    Cast(x, _, _, _) => walk_expr(x, out)
    InitList(elems, _, _) =>
      for el in elems {
        // 指派符（Designator::Index 携带表达式——索引域求值序）
        for d in el.designators {
          match d {
            Index(x) => walk_expr(x, out)
            Field(_) => ()
          }
        }
        walk_expr(el.value, out)
      }
    Offsetof(_, _, _, _) => ()
    Generic(c, assoc, dflt, _, _) => {
      walk_expr(c, out)
      for pair in assoc {
        walk_expr(pair.1, out)
      }
      match dflt {
        Some(x) => walk_expr(x, out)
        None => ()
      }
    }
    CompoundLiteral(_, init, _, _) => walk_expr(init, out)
    // === C++（C 子集零到达——防御面同构遍历）===
    This(_, _) => ()
    New(_, size, init, _, _) => {
      match size {
        Some(x) => walk_expr(x, out)
        None => ()
      }
      match init {
        Some(x) => walk_expr(x, out)
        None => ()
      }
    }
    Delete(x, _, _, _) => walk_expr(x, out)
    Lambda(_, _, body, _, _, _) => walk_stmt(body, out)
    Move(x, _, _) => walk_expr(x, out)
  }
}
