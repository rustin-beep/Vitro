///|
/// #142/#151（2026-10-18）：静态存储期初始化器的常量表达式求值与诊断。
///
/// 背景（LLM 探针批实锤）：文件作用域 / 函数内 static 的初始化器只要
/// 含表达式（算术/宏/sizeof），codegen 的 literal_init_bits 只认字面量
/// 形态、其余静默置 0（#142 值错）；而非常量形态（函数调用/变量引用）
/// 又零诊断放行（#151 误收）。C11 §6.6/§6.7.9p4 要求静态初始化器为
/// 常量表达式——本文件补齐 typeck 层的求值（折成字面量节点交给
/// codegen 既有字面量路径）与诊断（E3075）。
///
/// 设计：求值器**无 Identifier 臂**——枚举常量已被 parser 在解析时折成
/// 字面量叶（parser/fold_enum.mbt，#135 同款结论：enum 物化全局与普通
/// int 全局 AST 同形不可区分）；到达此处的 Identifier 一律视为非常量，
/// 由 diagnose 按「命中普通变量/含函数调用」报 E3075（函数名地址常量
/// 与 & 取址族合法不报——`int (*pf)(void) = f;` / `int *p = &g;`）。

///|
/// 常量值域：整（Int64——int/long long/char 统一）与浮（Double）。
priv enum CVal {
  CI(Int64)
  CF(Double)
}

///|
/// 求值栈帧（迭代化——病 40 教训：递归版在 ~2 万层深链栈溢出，形态
/// 对齐 parser const_int_of 的显式栈后序）。
priv enum CEvalFrame {
  CE_E(@ast.Expr)
  /// ty = 一元结果类型（P1-2：Neg/BitNot 后按类型归一）
  CE_AppU(@ast.UnaryOp, @ast.Type)
  /// lty/rty = 左右操作数类型（比较/除法/右移的符号域判定），
  /// resty = 结果类型（算术后按宽度归一）——P1-2 符号性对偶
  CE_AppB(@ast.BinaryOp, @ast.Type, @ast.Type, @ast.Type)
  /// Ternary 条件值已弹后按真值压选中分支
  CE_TernSel(@ast.Expr, @ast.Expr)
  CE_Cast(@ast.Type)
}

///|
/// 整类型的 unsigned 位（浮点/其他非整型恒 false——浮点无符号域）。
fn ce_is_unsigned(ty : @ast.Type) -> Bool {
  match ty.kind() {
    TK_Char | TK_Int | TK_LongLong => ty.is_unsigned()
    _ => false
  }
}

///|
/// 值按类型宽度/符号性归一（P1-2）：u32 → 低 32 位零扩展（位模式语义
/// 值 4294967295 域）、i32 → 32 位符号扩展、char 同款 8 位、64 位类型
/// 不动。64 位容器内保持位模式一致是算术可先算后归一的依据。
fn ce_normalize(i : Int64, ty : @ast.Type) -> Int64 {
  match ty.kind() {
    TK_Char => if ty.is_unsigned() { i & 0xFFL } else { i << 56 >> 56 }
    TK_Int => if ty.is_unsigned() { i & 0xFFFFFFFFL } else { i << 32 >> 32 }
    _ => i
  }
}

///|
/// 常量表达式求值（C11 §6.6 教学子集）：整/浮字面量、一元
/// Neg·Pos·Not·BitNot、二元算术·位·移位·比较·逻辑（结果 0/1）、
/// 三元、sizeof/alignof（compute_type_size）、整↔浮 Cast。
/// 求不出（非常量/除零/移位量越界）返回 None——调用方决定折叠失败
/// 后的诊断策略。浮点比较与混合运算按 C 语义升 double 域。
fn TypeChecker::const_eval(self : TypeChecker, expr : @ast.Expr) -> CVal? {
  let st : Array[CEvalFrame] = [CE_E(expr)]
  let vals : Array[CVal] = []
  while st.length() > 0 {
    match st.pop() {
      None => break
      Some(CE_AppU(op, ty)) => {
        let v = match vals.pop() {
          Some(v) => v
          None => return None
        }
        match (op, v) {
          (Neg, CI(i)) => vals.push(CI(ce_normalize(i.neg(), ty)))
          (Neg, CF(f)) => vals.push(CF(-f))
          (Pos, v) => vals.push(v) // 恒等（#71 病 39）
          (Not, CI(i)) => vals.push(CI(if i == 0 { 1L } else { 0L }))
          (BitNot, CI(i)) => vals.push(CI(ce_normalize(-1L * (i + 1L), ty))) // 二补码代数式
          _ => return None // 位非/逻辑非的浮点操作数：教学域罕见，不折
        }
      }
      Some(CE_AppB(op, lty, rty, resty)) => {
        let b = match vals.pop() {
          Some(v) => v
          None => return None
        }
        let a = match vals.pop() {
          Some(v) => v
          None => return None
        }
        // 任一侧浮点 → double 域（C usual arithmetic promotions 简化）
        match (a, b) {
          (CI(x), CI(y)) => {
            // P1-2：整型混合符号——usual conversions 任一侧 unsigned 即
            // 升无符号域（位模式按 UInt64 重解释比较/除法/右移）
            let u_domain = ce_is_unsigned(lty) || ce_is_unsigned(rty)
            let xu = x.reinterpret_as_uint64()
            let yu = y.reinterpret_as_uint64()
            match op {
              Add => vals.push(CI(ce_normalize(x + y, resty)))
              Sub => vals.push(CI(ce_normalize(x - y, resty)))
              Mul => vals.push(CI(ce_normalize(x * y, resty)))
              Div =>
                if y != 0 {
                  vals.push(
                    CI(
                      ce_normalize(
                        if u_domain {
                          (xu / yu).reinterpret_as_int64()
                        } else {
                          x / y
                        },
                        resty,
                      ),
                    ),
                  )
                } else {
                  return None
                }
              Mod =>
                if y != 0 {
                  vals.push(
                    CI(
                      ce_normalize(
                        if u_domain {
                          (xu % yu).reinterpret_as_int64()
                        } else {
                          x % y
                        },
                        resty,
                      ),
                    ),
                  )
                } else {
                  return None
                }
              BitAnd => vals.push(CI(ce_normalize(x & y, resty)))
              BitOr => vals.push(CI(ce_normalize(x | y, resty)))
              BitXor => vals.push(CI(ce_normalize(x ^ y, resty)))
              Shl =>
                if y >= 0 && y <= 63 {
                  vals.push(CI(ce_normalize(x << y.to_int(), resty)))
                } else {
                  return None
                }
              Shr =>
                if y >= 0 && y <= 63 {
                  // 逻辑右移（u_domain）/ 算术右移（signed）
                  vals.push(
                    CI(
                      ce_normalize(
                        if u_domain {
                          (xu >> y.to_int()).reinterpret_as_int64()
                        } else {
                          x >> y.to_int()
                        },
                        resty,
                      ),
                    ),
                  )
                } else {
                  return None
                }
              Lt => {
                let hit = if u_domain { xu < yu } else { x < y }
                vals.push(CI(if hit { 1L } else { 0L }))
              }
              Le => {
                let hit = if u_domain { xu <= yu } else { x <= y }
                vals.push(CI(if hit { 1L } else { 0L }))
              }
              Gt => {
                let hit = if u_domain { xu > yu } else { x > y }
                vals.push(CI(if hit { 1L } else { 0L }))
              }
              Ge => {
                let hit = if u_domain { xu >= yu } else { x >= y }
                vals.push(CI(if hit { 1L } else { 0L }))
              }
              Eq => vals.push(CI(if x == y { 1L } else { 0L }))
              Ne => vals.push(CI(if x != y { 1L } else { 0L }))
              And => vals.push(CI(if x != 0 && y != 0 { 1L } else { 0L }))
              Or => vals.push(CI(if x != 0 || y != 0 { 1L } else { 0L }))
              _ => return None
            }
          }
          _ => {
            // 浮点域（至少一侧 CF）
            let xf = to_f64(a)
            let yf = to_f64(b)
            match op {
              Add => vals.push(CF(xf + yf))
              Sub => vals.push(CF(xf - yf))
              Mul => vals.push(CF(xf * yf))
              Div => vals.push(CF(xf / yf))
              Lt => vals.push(CI(if xf < yf { 1L } else { 0L }))
              Le => vals.push(CI(if xf <= yf { 1L } else { 0L }))
              Gt => vals.push(CI(if xf > yf { 1L } else { 0L }))
              Ge => vals.push(CI(if xf >= yf { 1L } else { 0L }))
              Eq => vals.push(CI(if xf == yf { 1L } else { 0L }))
              Ne => vals.push(CI(if xf != yf { 1L } else { 0L }))
              _ => return None // 位/移位/取模的浮点操作数非 C 合法形态
            }
          }
        }
      }
      Some(CE_TernSel(then_e, else_e)) => {
        let c = match vals.pop() {
          Some(CI(i)) => i != 0
          Some(CF(f)) => f != 0.0
          None => return None
        }
        st.push(CE_E(if c { then_e } else { else_e }))
      }
      Some(CE_Cast(target)) => {
        let v = match vals.pop() {
          Some(v) => v
          None => return None
        }
        match target.kind() {
          TK_Double | TK_Float =>
            match v {
              CI(i) => vals.push(CF(i.to_double()))
              CF(f) => vals.push(CF(f))
            }
          _ =>
            match v {
              // 截断语义（C 浮→整转换；超界环绕与 clang 常量折叠口径
              // 差异由对拍暴露再登记）
              CF(f) => vals.push(CI(ce_normalize(f.to_int64(), target)))
              // P1-2：整→整 cast 按目标宽度/符号性归一——旧恒等臂丢
              // unsigned 位（`(unsigned)-1` 值域该 4294967295）
              CI(i) => vals.push(CI(ce_normalize(i, target)))
            }
        }
      }
      Some(CE_E(e)) =>
        match e {
          Literal(v, _, _) => vals.push(CI(v.to_int64()))
          LongLiteral(v, _, _) => vals.push(CI(v))
          FloatLiteral(v, _, _) => vals.push(CF(v))
          Unary(op, inner, _, ty) => {
            st.push(CE_AppU(op, ty))
            st.push(CE_E(inner))
          }
          Binary(op, l, r, _, ty) => {
            st.push(CE_AppB(op, l.ty(), r.ty(), ty))
            st.push(CE_E(r))
            st.push(CE_E(l))
          }
          Ternary(c, t, el, _, _) => {
            st.push(CE_TernSel(t, el))
            st.push(CE_E(c))
          }
          Cast(inner, target, _, _) => {
            st.push(CE_Cast(target))
            st.push(CE_E(inner))
          }
          Sizeof(target_type, operand, _, _) => {
            let size : Int32 = match target_type {
              Some(t) => self.compute_type_size(t)
              None =>
                match operand {
                  // #265（2026-10-22）：声明类型里的 vla_dims（`(int)(sizeof
                  // ARR / sizeof ARR[0])` 维数惯用法）未经 resolve——
                  // Identifier/Index 的 ty 未定型，查符号表取真类型
                  //（`sizeof ARR[0]` 的 Index 节点取下标一次后的元素类型）
                  Some(Identifier(name, _, _)) =>
                    match self.lookup_var(name) {
                      Some(sym) => self.compute_type_size(sym.ty)
                      None => return None
                    }
                  Some(Index(Identifier(name, _, _), _, _, _)) =>
                    match self.lookup_var(name) {
                      Some(sym) if sym.ty.is_array() =>
                        self.compute_type_size(sym.ty.subscript_type())
                      _ => return None
                    }
                  // 求值时机在 resolve 之后：operand.ty() 已定型
                  Some(op_expr) => self.compute_type_size(op_expr.ty())
                  None => return None
                }
            }
            if size <= 0 {
              return None
            }
            vals.push(CI(size.to_int64()))
          }
          Alignof(_, _, _, _) =>
            // alignof 与 sizeof 同域（自然对齐）；教学面罕见，取 4/8
            // 简化值不可靠——不折，登记（#52 时间旅行面另有对齐口径）
            return None
          // Identifier（enum 已被 parser 折掉；变量/函数名非常量）、
          // Call/Member/Index/StringLiteral/赋值等：非常量
          _ => return None
        }
    }
  }
  match vals.pop() {
    Some(v) if vals.length() == 0 => Some(v)
    _ => None
  }
}

///|
fn to_f64(v : CVal) -> Double {
  match v {
    CI(i) => i.to_double()
    CF(f) => f
  }
}

///|
/// 折叠静态初始化器：求值成功 → 按目标类型造字面量节点（codegen 的
/// literal_init_bits 既有路径直接消费）；失败 → 诊断后原样返回。
/// 目标类型按 kind 选节点形态：int/char/指针按 i32 截断 Literal、
/// long long 用 LongLiteral、float/double 用 FloatLiteral。
fn TypeChecker::fold_static_init(
  self : TypeChecker,
  target : @ast.Type,
  init : @ast.Expr,
) -> @ast.Expr {
  let folded = match self.const_eval(init) {
    Some(v) => {
      let loc = init.loc()
      let keep_ty = init.ty()
      match (v, target.kind()) {
        (CI(i), TK_LongLong) => Some(@ast.Expr::LongLiteral(i, loc, keep_ty))
        (CI(i), TK_Double) =>
          Some(@ast.Expr::FloatLiteral(i.to_double(), loc, keep_ty))
        (CI(i), TK_Float) =>
          Some(@ast.Expr::FloatLiteral(i.to_double(), loc, keep_ty))
        (CI(i), _) =>
          Some(@ast.Expr::Literal(@util.i64_to_i32_bits(i), loc, keep_ty))
        (CF(f), TK_Double | TK_Float) =>
          Some(@ast.Expr::FloatLiteral(f, loc, keep_ty))
        (CF(f), _) => Some(@ast.Expr::LongLiteral(f.to_int64(), loc, keep_ty))
      }
    }
    None => None
  }
  match folded {
    Some(node) => node
    None => {
      self.diagnose_static_init(init)
      init
    }
  }
}

///|
/// 聚合初始化器递归折叠（数组/struct/union 的静态初始化）：标量元素
/// 按元素目标类型折；嵌套 InitList 递归；designator 不影响元素类型
/// 定位（数组元素类型统一 inner；struct 字段按位置序或 .field 名查）。
fn TypeChecker::fold_static_aggregate(
  self : TypeChecker,
  target : @ast.Type,
  init : @ast.Expr,
) -> @ast.Expr {
  match init {
    InitList(elements, loc, ty) => {
      let folded : Array[@ast.InitElement] = []
      if target.kind() is TK_Struct || target.kind() is TK_Union {
        let fields : Array[@ast.Type] = match self.structs.get(target.name()) {
          Some(sym) => sym.fields.map(f => f.0)
          None =>
            match self.unions.get(target.name()) {
              Some(sym) => sym.fields.map(f => f.0)
              None => []
            }
        }
        let mut cursor = 0
        for elem in elements {
          let field_ty : @ast.Type? = if elem.designators.length() > 0 {
            match elem.designators[0] {
              Field(fname) => find_field_ty(self, target, fname)
              _ => None
            }
          } else {
            let cur = cursor
            cursor += 1
            if cur < fields.length() {
              Some(fields[cur])
            } else {
              None
            }
          }
          match field_ty {
            Some(ft) =>
              folded.push({
                ..elem,
                value: self.fold_static_elem(ft, elem.value),
              })
            None => folded.push(elem)
          }
        }
      } else if target.is_array() {
        let inner = target.subscript_type()
        for elem in elements {
          folded.push({
            ..elem,
            value: self.fold_static_elem(inner, elem.value),
          })
        }
      } else {
        // 标量目标的单元素列表（C11 6.7.9p11）——按目标折首元素
        for i, elem in elements {
          if i == 0 {
            folded.push({
              ..elem,
              value: self.fold_static_elem(target, elem.value),
            })
          } else {
            folded.push(elem)
          }
        }
      }
      InitList(folded, loc, ty)
    }
    _ => self.fold_static_init(target, init)
  }
}

///|
/// 单元素折叠分派：嵌套聚合递归 / 标量按 fold_static_init。
fn TypeChecker::fold_static_elem(
  self : TypeChecker,
  target : @ast.Type,
  value : @ast.Expr,
) -> @ast.Expr {
  match value {
    InitList(_, _, _) => self.fold_static_aggregate(target, value)
    StringLiteral(_, _, _) => value // char[] 专门路径（#75 缺口 3）
    _ =>
      if target.kind() is TK_Struct ||
        target.kind() is TK_Union ||
        target.is_array() {
        // struct 变量/聚合值元素：非常量（诊断面按变量引用报）
        self.diagnose_static_init(value)
        value
      } else {
        self.fold_static_init(target, value)
      }
  }
}

///|
/// 按 .field 名查字段类型（structs/unions 符号的 (ty, name) 平行表）。
fn find_field_ty(
  tc : TypeChecker,
  target : @ast.Type,
  fname : String,
) -> @ast.Type? {
  let fields = match tc.structs.get(target.name()) {
    Some(sym) => sym.fields
    None =>
      match tc.unions.get(target.name()) {
        Some(sym) => sym.fields
        None => return None
      }
  }
  for pair in fields {
    if pair.1 == fname {
      return Some(pair.0)
    }
  }
  // #266（2026-10-22）：静态聚合 designated（`.a = 常量`）指名匿名成员
  // 内部成员——穿透查找（与 check_struct_initializer designated 分支
  // 同语义；成员访问面 #7 销案同源）
  tc.find_anonymous_member(target.name(), target.kind() is TK_Union, fname, 0)
}

///|
/// #151 诊断：静态初始化器非常量形态报 E3075。判据收窄（防误拒优先）：
/// - Call（函数调用）出现在表达式树 → 报（静态初始化域恒非法）
/// - Identifier 命中普通变量（enum 已折、函数名放行、未声明放行——
///   E3023 已报不双报）→ 报
/// - Unary(Addr, ..) 合法（地址常量族：`&g` / `f` / `&arr[i]`）——但
///   #331（2026-10-27）起 base 标识符做声明序守卫：前向引用（声明点
///   在后）报 E3023，对齐 clang use-before-declaration
/// - Index/Member/Deref 裸用（`arr[0]` / `s.x`）与除零等求值失败：
///   不报（保守，登记渐进）
fn TypeChecker::diagnose_static_init(
  self : TypeChecker,
  expr : @ast.Expr,
) -> Unit {
  match expr {
    Call(name, args, _, _) => {
      self.report_error(
        "初始化器含函数调用 '\{name}'，静态存储期对象的初始化器必须是编译期常量表达式",
        expr.loc(),
        E3075_StaticInitNotConstant,
      )
      for a in args {
        self.diagnose_static_init(a)
      }
    }
    CallPtr(callee, _, _, _) => {
      // C 调用统一在 CallPtr 臂（Expr::Call 仅 C++ ctor 路径可达——
      // codegen 分区手册同结论）；静态初始化器里函数指针调用同族非法
      self.report_error(
        "初始化器含函数调用，静态存储期对象的初始化器必须是编译期常量表达式",
        expr.loc(),
        E3075_StaticInitNotConstant,
      )
      self.diagnose_static_init(callee)
    }
    Identifier(name, _, _) => {
      let is_func = self.funcs.contains(name) ||
        self.static_func_sigs.contains(name)
      if !is_func && self.lookup_var(name) is Some(sym) {
        // #264（2026-10-22）：数组名是地址常量——C23 §6.6p9（数组右值
        // 退化为指向首元素的指针，指向静态存储期对象），静态初始化器
        // 合法形态（静态规格表互引用的标准写法）；值回填在 codegen
        // flatten_global_init 的地址常量路径
        if !sym.ty.is_array() {
          self.report_error(
            "初始化器引用了变量 '\{name}'，静态存储期对象的初始化器必须是编译期常量表达式",
            expr.loc(),
            E3075_StaticInitNotConstant,
          )
        } else {
          // #331（2026-10-27）：数组名地址常量的前向引用守卫（声明点
          // 在当前初始化器所属声明之后 = C11 6.2.1p4 不可见）
          self.check_fwd_ref_decl_order(name, expr.loc())
        }
      }
    }
    Unary(op, inner, _, _) =>
      if op is @ast.UnaryOp::Addr {
        // 地址常量族：合法形态不诊断——但 #331：base 标识符做声明序
        // 守卫（两段式登记下前向引用的 &s / 数组名 / 链形态 base 此前
        // 被 codegen pending 回填静默接受）
        self.check_addr_base_decl_order(inner)
      } else {
        self.diagnose_static_init(inner)
      }
    Binary(_, l, r, _, _) => {
      self.diagnose_static_init(l)
      self.diagnose_static_init(r)
    }
    Ternary(c, t, e, _, _) => {
      self.diagnose_static_init(c)
      self.diagnose_static_init(t)
      self.diagnose_static_init(e)
    }
    Cast(inner, _, _, _) => self.diagnose_static_init(inner)
    Sizeof(_, Some(op_expr), _, _) => self.diagnose_static_init(op_expr)
    InitList(elements, _, _) =>
      for elem in elements {
        self.diagnose_static_init(elem.value)
      }
    _ => ()
  }
}

///|
/// #331（2026-10-27）：地址常量初始化器的 base 声明序守卫——剥 Member/
/// Index 链（`&s.x` / `&sa[1].m`）取尾 base 标识符；链上出现其他节点
///（Deref 包裹的指针基座等）保守放行（与 codegen eval_global_addr_chain
/// 的链判定同构）。base 前向引用（首声明序在当前初始化器所属声明之后）
/// = C11 6.2.1p4 声明点之前不可见，对齐 clang use of undeclared
/// identifier。site 语境（static_init_site_idx）只在文件作用域检查段
/// 激活——函数内 static 的初始化器（Pass 4）不进守卫。
fn TypeChecker::check_addr_base_decl_order(
  self : TypeChecker,
  inner : @ast.Expr,
) -> Unit {
  let mut cur = inner
  while true {
    match cur {
      Member(obj, _, _, _, _) => cur = obj
      Index(arr, _, _, _) => cur = arr
      Identifier(name, _, _) => {
        self.check_fwd_ref_decl_order(name, cur.loc())
        break
      }
      _ => break
    }
  }
}

///|
/// #331：前向引用守卫判定单点——名字命中文件作用域首声明序表且其首
/// 声明序晚于当前检查位点（static_init_site_idx）时报 E3023。不在
/// global_first_decl_idx 表的名字（函数名 / 局部符号 / 真未声明——后者
/// E3023 已由 resolve 面另行报出不双报）放行；extern 先行声明（首声明
/// 序在前）自然通过——codegen 的 pending 回填通道（extern 形态活代码，
/// #331 销案评论突变实证）不受影响。
fn TypeChecker::check_fwd_ref_decl_order(
  self : TypeChecker,
  name : String,
  loc : @source.SourceLoc,
) -> Unit {
  match (self.global_first_decl_idx.get(name), self.static_init_site_idx) {
    (Some(first_idx), Some(site)) =>
      if first_idx > site {
        self.report_error(
          "未声明的标识符 '\{name}'（其首次声明位于本初始化器之后——文件作用域初始化器只能引用此前已声明的对象）",
          loc,
          E3023_UndeclaredVar,
        )
      }
    _ => ()
  }
}

///|
/// #265（2026-10-22）：VLA 维度的常量二次折叠。parser 的 const_int_of
/// 无 Cast/Sizeof 臂——`(int)(sizeof arr / sizeof arr[0])`（C 求数组长
/// 度的标准惯用法，C23 §6.6 整型常量表达式）折不出被误判 VLA（dims 落
/// 0 哨兵 + is_vla=true），下游三面连坐：decay 判等（type_eq 含
/// is_vla、subscript_type 传导）误拒 E3038 / 全局被 codegen 拒「不支持
/// VLA」/ struct 成员 stride 落 0 哨兵运行时 trap。typeck 层 const_eval
/// 支持 Cast/Sizeof/Ternary（含 #265 的 sizeof 符号表回退），此处对
/// vla_dims 逐维再折；**全部维度折出正整数**才回填定长（部分折出维持
/// VLA——parser size 状态机「最外维 0 恒 0」的语义不在此重算，混合
/// 形态教学域罕见、维持既有运行时求值路径）。
///
/// vla_dims 与 dims 的 0 哨兵维按序一一对应（parser array_prepend_dim
/// 头插同序保证；显式 `[0]` 零长数组 is_vla=false 不进此路径）。
fn TypeChecker::refold_vla_const_dims(
  self : TypeChecker,
  ty : @ast.Type,
) -> @ast.Type {
  match ty {
    Array(element, _, dims, is_const, is_vla, vla_dims) => {
      if !is_vla || vla_dims.is_empty() {
        return ty
      }
      let new_dims : Array[Int32] = []
      for d in dims {
        new_dims.push(d)
      }
      let mut cursor = 0
      let mut all_folded = true
      for i in 0..<new_dims.length() {
        if new_dims[i] == 0 && cursor < vla_dims.length() {
          match self.const_eval(vla_dims[cursor]) {
            Some(CI(v)) =>
              if v > 0L && v <= 2147483647L {
                new_dims[i] = @util.i64_to_i32_bits(v)
              } else {
                all_folded = false
              }
            // 浮点维度非 C 合法维数形态：不折（VLA 路径承接）
            Some(CF(_)) => all_folded = false
            None => all_folded = false
          }
          cursor += 1
        }
      }
      // 0 哨兵维与 vla_dims 未对齐消费（形态异常）或折不全：不动
      if !all_folded || cursor != vla_dims.length() {
        return ty
      }
      let mut size = 1
      for d in new_dims {
        size *= d
      }
      Array(element, size, new_dims, is_const, false, [])
    }
    _ => ty
  }
}

///|
/// #144：收集 switch 体直层的 case 标签（值经 const_eval 折 Int64）。
/// 递归只走 Block/Case/Label 链——C 语法 case 只出现在 switch 直接体
/// （可嵌 Block）；**遇嵌套 Switch 停**（内层标签归内层自查，防跨层
/// 误报）。求不出值的标签跳过（E3047 常量性检查另行报）。
fn collect_case_labels(
  tc : TypeChecker,
  stmt : @ast.Stmt,
  labels : Array[(Int64, @source.SourceLoc)],
) -> Int32 {
  let mut default_count = 0
  match stmt {
    Case(label, inner, _) => {
      match label {
        Some(e) =>
          match tc.const_eval(e) {
            Some(CI(v)) => labels.push((v, e.loc()))
            // 浮点 case 标签：E3046/E3047 已报，占位参与查重
            Some(CF(_)) => labels.push((0L, e.loc()))
            None => ()
          }
        None => default_count = default_count + 1
      }
      default_count += collect_case_labels(tc, inner, labels)
    }
    Block(stmts, _) =>
      for s in stmts {
        default_count += collect_case_labels(tc, s, labels)
      }
    Label(_, inner, _) =>
      default_count += collect_case_labels(tc, inner, labels)
    _ => ()
  }
  default_count
}

///|
/// #265/P1-5（审阅批 2026-10-23）：struct/union 成员维数折叠的延迟执行
/// 点——在全局符号登记与尺寸推断定型后由 check 主流程调用（注册期
/// lookup_var 扑空只覆盖纯 cast 面）。折后回写 program 声明与
/// structs/unions 符号表（is_complete 保持注册时值）。
fn TypeChecker::defer_refold_members(
  self : TypeChecker,
  program : @ast.ProgramNode,
) -> Unit {
  for si in 0..<program.structs.length() {
    let s = program.structs[si]
    if s.is_forward {
      continue
    }
    let mut changed = false
    let folded : Array[@ast.StructField] = []
    for f in s.fields {
      let fty = self.refold_vla_const_dims(f.ty)
      if fty is Array(_, _, _, _, false, _) &&
        f.ty is Array(_, _, _, _, true, _) {
        changed = true
      }
      folded.push({ ..f, ty: fty, })
    }
    if changed {
      program.structs[si] = { ..s, fields: folded, }
      match self.structs.get(s.name) {
        Some(sym) =>
          self.structs.set(s.name, {
            fields: folded.map(f => (f.ty, f.name)),
            is_complete: sym.is_complete,
          })
        None => ()
      }
    }
  }
  for ui in 0..<program.unions.length() {
    let u = program.unions[ui]
    if u.is_forward {
      continue
    }
    let mut changed = false
    let folded : Array[@ast.StructField] = []
    for f in u.fields {
      let fty = self.refold_vla_const_dims(f.ty)
      if fty is Array(_, _, _, _, false, _) &&
        f.ty is Array(_, _, _, _, true, _) {
        changed = true
      }
      folded.push({ ..f, ty: fty, })
    }
    if changed {
      program.unions[ui] = { ..u, fields: folded, }
      match self.unions.get(u.name) {
        Some(sym) =>
          self.unions.set(u.name, {
            fields: folded.map(f => (f.ty, f.name)),
            is_complete: sym.is_complete,
          })
        None => ()
      }
    }
  }
}
