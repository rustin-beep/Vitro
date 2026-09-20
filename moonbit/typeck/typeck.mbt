///|
/// L5 类型检查主包（`vitro/engine/typeck`）——**C 子集**（S4 范围裁定：
/// v1 = C only，F-2；C++ 专属 ~3534 行延后 S9 裁定批）。
///
/// 职责（勘察 §0 P-2 纠偏后的准确表述）：命名解析 + 类型检查 + **AST→AST
/// 改写（lowering）**——插入隐式 Cast、数组尺寸推断、ty 定型。
///
/// 形态决策（S4 核心技术裁定）：
/// - Rust 侧 88 处 AST 字段就地赋值（`*ty =` / `*expr =`）在 MoonBit 值
///   语义 enum 下**无对应通道**——lowering 采用**函数式重建**：visitor
///   值进值出（`resolve_expr_type(Expr) -> (Type, Expr)` 等），父节点
///   重建携带改写后的子树。等价性由 E4 锚（类型化 AST 全量对拍）保证。
/// - TypeChecker 本体照搬 Rust 可变 visitor 形态（可变 Map 符号表 +
///   mut 上下文标量——S3 parser 先例：core Map 可变 + `.copy()` 快照）。
/// - 诊断三段（errors/warnings/hints）push 序保序 = E1 对拍面。
///
/// Pass 编排（C 子集 4 Pass；Rust 13 Pass 剔除 C++ 九个：1.5 类布局/
/// 1.6 类外方法合并/2.4 类静态字段/2.6 模板注册/2.65 显式实例化/
/// 3 期 drain/3.5 类方法/3.55 隐式移动构造/3.6 实例化收敛/4 lambda——
/// 剔除点逐一登记于执行记录）：
///   Pass 1   struct/union 注册 + 重复定义 + T-P0-8 值成员环检测
///   Pass 2   函数签名注册（static 与普通两轨）
///   Pass 2.5 全局变量登记 + 数组尺寸合法性 + 初始化器检查
///   Pass 3   函数体检查
///
/// **本批边界（红→绿推进中间态）**：Pass 1/2 全量 + Pass 2.5 的登记与
/// dims 合法性已落地；表达式解析（resolve_expr_type）与初始化器检查、
/// Pass 3 函数体 visitor 随下一批（expr/decl/init 族）接线——当前对
/// 这些面**直通不检查**（typed_ast 原样、诊断三段不含其产物）。

///|
/// 类型错误帧（照搬 Rust `TypeError`：message/line/column/code——无
/// file_id、无 span 是 O4 登记债，协议层不动）。
pub(all) struct TypeError {
  message : String
  line : Int
  column : Int
  code : Int
}

///|
/// 类型检查器（C 子集字段集——Rust 27 字段中剔除 C++ 十一项：
/// classes/templates/current_class/current_method_is_const/四件套实例化
/// 队列/pending_lambdas/is_library_mode）。
pub struct TypeChecker {
  // 符号表（core Map 可变哈希——内容变更不需 mut 字段）
  funcs : Map[String, FuncSymbol]
  static_func_sigs : Map[String, FuncSymbol]
  static_func_files : Map[String, Array[String]]
  static_global_files : Map[String, Array[String]]
  structs : Map[String, StructSymbol]
  unions : Map[String, StructSymbol]
  // 作用域栈
  scopes : Array[Map[String, VarSymbol]]
  // 上下文标量（Rust 同名照搬——visitor 期间可变）
  mut current_func_return : @ast.Type?
  mut current_file : String
  mut loop_depth : Int
  mut switch_depth : Int
  // 当前函数形参名集合（sizeof 的数组形参退化 W3052 判据；visit_func_decl
  // 填充/清空——Rust lib.rs:45，骨架批漏项本批补）
  current_func_params : Set[String]
  mut char_narrow_suppress : Bool
  // goto/label 闭合检查（visit_func_decl 填充/清空；Rust lib.rs:46-47）
  func_labels : Map[String, @source.SourceLoc]
  pending_gotos : Array[(String, @source.SourceLoc)]
  // 诊断三段（push 序 = E1 对拍面）
  errors : Array[TypeError]
  warnings : Array[TypeError]
  hints : Array[TypeError]
}

///|
pub fn TypeChecker::new() -> TypeChecker {
  {
    funcs: Map([]),
    static_func_sigs: Map([]),
    static_func_files: Map([]),
    static_global_files: Map([]),
    structs: Map([]),
    unions: Map([]),
    scopes: [],
    current_func_return: None,
    current_file: "",
    loop_depth: 0,
    switch_depth: 0,
    current_func_params: Set([]),
    char_narrow_suppress: false,
    func_labels: Map([]),
    pending_gotos: [],
    errors: [],
    warnings: [],
    hints: [],
  }
}

///|
/// 主入口（值进值出）：C 子集 4 Pass。返回三段诊断；入参 program 返回
/// 改写后的 program（lowering 结果 = E4 面）。
pub fn TypeChecker::check(
  self : TypeChecker,
  program : @ast.ProgramNode,
) -> (@ast.ProgramNode, Array[TypeError], Array[TypeError], Array[TypeError]) {
  // Pass 1: struct/union 注册
  for s in program.structs {
    if self.structs.contains(s.name) {
      self.report_error(
        "结构体 '\{s.name}' 重复定义",
        s.loc,
        E3002_StructRedeclared,
      )
      continue
    }
    self.structs.set(s.name, { fields: s.fields.map(f => (f.ty, f.name)), })
  }
  for u in program.unions {
    if self.unions.contains(u.name) {
      self.report_error(
        "联合体 '\{u.name}' 重复定义",
        u.loc,
        E3002_StructRedeclared,
      )
      continue
    }
    self.unions.set(u.name, { fields: u.fields.map(f => (f.ty, f.name)), })
  }
  // T-P0-8：struct/union 值成员循环包含检测（学生写链表节点漏 `*` 的
  // 经典错误，曾致 compute_type_size 无限递归栈溢出）。
  // 环检测遍历**符号表首版**（sym.fields）而非当前声明——重复定义时
  // 两者不同，Rust lib.rs:139-141 同构（审阅 F1：遍历声明会在"次版自环"
  // 多报假 E3072、"首版自环"漏报，双向分叉）。
  for s in program.structs {
    match self.structs.get(s.name) {
      Some(sym) => {
        let path : Array[String] = [s.name]
        match self.value_member_cycle_first(sym.fields.map(f => f.0), path) {
          Some(cycle) =>
            self.report_error(
              "结构体 '\{s.name}' 的值成员存在循环包含（经 '\{cycle}' 回到自身）：结构体不能按值包含自己，链表/树节点请改用指针成员，如 `struct \{s.name}* next;`",
              s.loc,
              E3072_StructSelfContain,
            )
          None => ()
        }
      }
      None => ()
    }
  }
  for u in program.unions {
    match self.unions.get(u.name) {
      Some(sym) => {
        let path : Array[String] = [u.name]
        match self.value_member_cycle_first(sym.fields.map(f => f.0), path) {
          Some(cycle) =>
            self.report_error(
              "联合体 '\{u.name}' 的值成员存在循环包含（经 '\{cycle}' 回到自身），请改用指针成员",
              u.loc,
              E3072_StructSelfContain,
            )
          None => ()
        }
      }
      None => ()
    }
  }
  // Pass 2: 函数签名注册
  for f in program.funcs {
    let new_sym : FuncSymbol = {
      return_type: f.return_type,
      param_types: f.params.map(p => p.ty),
      is_variadic: f.is_variadic,
      param_defaults: f.params.map(p => p.default),
    }
    if f.is_static {
      match self.static_func_sigs.get(f.name) {
        Some(existing) =>
          if !@ast.type_eq(existing.return_type, new_sym.return_type) ||
            !params_eq(existing.param_types, new_sym.param_types) {
            self.report_error(
              "函数 '\{f.name}' 的声明与之前定义签名不一致",
              f.loc,
              E3003_FuncRedeclared,
            )
          }
        None => self.static_func_sigs.set(f.name, new_sym)
      }
      match self.static_func_files.get(f.name) {
        Some(files) => files.push(f.source_file)
        None => self.static_func_files.set(f.name, [f.source_file])
      }
    } else {
      match self.funcs.get(f.name) {
        Some(existing) =>
          if !@ast.type_eq(existing.return_type, new_sym.return_type) ||
            !params_eq(existing.param_types, new_sym.param_types) {
            self.report_error(
              "函数 '\{f.name}' 的声明与之前定义签名不一致",
              f.loc,
              E3003_FuncRedeclared,
            )
          }
        None => self.funcs.set(f.name, new_sym)
      }
    }
  }
  // Pass 2.5: Register globals and check initializers（Rust lib.rs
  // 273-349 全量——call/init 批接线完成，直通守卫全部移除）。
  // 条目 2（2026-09-11 照搬）：全局 auto/typeof 变量必须**先用初始化器
  // 定型再登记**；初始化器只解析一次，结果缓存给下面的检查循环复用
  // ——重复解析 = 诊断双份。
  self.enter_scope()
  let precomputed_init_types : Map[String, @ast.Type] = Map([])
  for i in 0..<program.globals.length() {
    let g = program.globals[i]
    if g.init is Some(init) {
      if type_has_auto(g.ty) || type_has_typeof(g.ty) {
        let (init_ty, new_init) = self.resolve_expr_type(init)
        let mut new_ty = g.ty
        if type_has_auto(new_ty) {
          new_ty = replace_auto_in_type(new_ty, init_ty)
        }
        // auto 替换后再判 typeof（Rust 顺序——两个判定都作用于替换后 ty）
        if type_has_typeof(new_ty) {
          new_ty = resolve_typeof_in_type(new_ty, init_ty)
        }
        precomputed_init_types.set(g.name, init_ty)
        program.globals[i] = { ..g, ty: new_ty, init: Some(new_init), }
      }
    }
  }
  for i in 0..<program.globals.length() {
    let g = program.globals[i]
    self.declare_var(
      g.name,
      g.ty,
      is_global=true,
      is_extern=g.is_extern,
      is_static=g.is_static,
    )
    if g.is_static {
      match self.static_global_files.get(g.name) {
        Some(files) => files.push(g.source_file)
        None => self.static_global_files.set(g.name, [g.source_file])
      }
    }
  }
  for i in 0..<program.globals.length() {
    let g = program.globals[i]
    // U1#12：全局数组尺寸合法性——extern 不完整声明（extern int g[];）
    // 是合法的，跳过；无初始化器的 `int a[];` 全局定义必须报错
    if g.ty.is_array() && !g.is_extern {
      let has_init_list = g.init is Some(InitList(_, _, _)) ||
        g.init is Some(StringLiteral(_, _, _))
      self.check_array_dims_legality(g.ty, has_init_list, g.loc)
    }
    if g.init is Some(init) {
      if g.ty.is_array() {
        let (new_ty, new_init) = self.check_array_initializer(g.ty, init, g.loc)
        // P4：`char g[] = "str"` 的尺寸推断发生在 declare_var 之后——
        // 回写符号表，否则 sizeof(g) 用推断前快照恒 1
        self.update_var_type(g.name, new_ty)
        program.globals[i] = { ..g, ty: new_ty, init: Some(new_init), }
      } else if g.ty.kind() is TK_Struct && init is InitList(_, _, _) {
        let new_init = self.check_struct_initializer(g.ty, init, g.loc)
        program.globals[i] = { ..g, init: Some(new_init), }
      } else {
        // precomputed 命中者取缓存类型（init 已在首段解析改写）；未命中
        // 现场解析（改写存回）——Rust `resolve_expr_type(&mut init)` 的
        // 就地改写语义
        let init_type : @ast.Type = match precomputed_init_types.get(g.name) {
          Some(t) => t
          None => {
            let (t, new_init) = self.resolve_expr_type(init)
            program.globals[i] = { ..g, init: Some(new_init), }
            t
          }
        }
        let g_now = program.globals[i]
        let mut new_ty = g_now.ty
        if type_has_auto(new_ty) {
          new_ty = replace_auto_in_type(new_ty, init_type)
        }
        if type_has_typeof(new_ty) {
          new_ty = resolve_typeof_in_type(new_ty, init_type)
        }
        if !@ast.type_eq(new_ty, g_now.ty) {
          program.globals[i] = { ..g_now, ty: new_ty, }
        }
        if !self.check_assignable(new_ty, init_type, g.loc) {
          self.report_error(
            "类型不匹配：无法将 '\{init_type.to_c_string()}' 赋值给 '\{new_ty.to_c_string()}'",
            g.loc,
            E3004_TypeMismatch,
          )
        }
      }
    }
  }
  // Pass 3: Check function bodies（decl.mbt visit_func_decl——body 为
  // None 的存根声明跳过：include 存根注入与 extern 声明同此轨）
  for i in 0..<program.funcs.length() {
    if program.funcs[i].body is Some(_) {
      program.funcs[i] = self.visit_func_decl(program.funcs[i])
    }
  }
  self.exit_scope()
  (program, self.errors, self.warnings, self.hints)
}

///|
/// 参数类型序列判等。
fn params_eq(a : Array[@ast.Type], b : Array[@ast.Type]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    if !@ast.type_eq(a[i], b[i]) {
      return false
    }
  }
  true
}

///|
/// T-P0-8：沿"值语义 struct/union 成员"（含数组包裹）展开，检测循环包含
///（Rust `value_member_cycle` 同构——字段数组的 find_map 形态改首个命中
/// 循环）。返回路径中首先撞到的已存在节点名；指针/引用/函数不构成环。
fn TypeChecker::value_member_cycle_first(
  self : TypeChecker,
  tys : Array[@ast.Type],
  path : Array[String],
) -> String? {
  for ty in tys {
    match self.value_member_cycle(ty, path) {
      Some(hit) => return Some(hit)
      None => ()
    }
  }
  None
}

///|
fn TypeChecker::value_member_cycle(
  self : TypeChecker,
  ty : @ast.Type,
  path : Array[String],
) -> String? {
  let mut ty_ref = ty
  while true {
    match ty_ref {
      Array(element, _, _, _, _, _) => ty_ref = element
      Struct(name, _) | Union(name, _) => {
        if path.contains(name) {
          return Some(name)
        }
        let fields : Array[(@ast.Type, String)] = match self.structs.get(name) {
          Some(s) => s.fields
          None =>
            match self.unions.get(name) {
              Some(s) => s.fields
              None => []
            }
        }
        path.push(name)
        let hit = self.value_member_cycle_first(fields.map(f => f.0), path)
        let _ = path.pop()
        return hit
      }
      _ => return None
    }
  }
  None
}

///|
/// 诊断出口（push 序保序——E1 面）。
pub fn TypeChecker::report_error(
  self : TypeChecker,
  msg : String,
  loc : @source.SourceLoc,
  code : @diag.ErrorCode,
) -> Unit {
  self.errors.push({
    message: msg,
    line: loc.line,
    column: loc.column,
    code: code.code(),
  })
}

///|
pub fn TypeChecker::report_warning(
  self : TypeChecker,
  msg : String,
  loc : @source.SourceLoc,
  code : @diag.ErrorCode,
) -> Unit {
  // W0-4：隐式标量转换警告按（行, 码）去重——初始化列表逐元素报同一条
  // "可能丢失精度"只会淹没真正有价值的诊断（同行第二条起丢弃）。
  if code is W3053_ImplicitScalarConversion {
    for w in self.warnings {
      if w.code == code.code() && w.line == loc.line {
        return
      }
    }
  }
  self.warnings.push({
    message: msg,
    line: loc.line,
    column: loc.column,
    code: code.code(),
  })
}

///|
pub fn TypeChecker::report_hint(
  self : TypeChecker,
  msg : String,
  loc : @source.SourceLoc,
  code : @diag.ErrorCode,
) -> Unit {
  self.hints.push({
    message: msg,
    line: loc.line,
    column: loc.column,
    code: code.code(),
  })
}

///|
/// U1#12：数组声明尺寸合法性（三形状：负尺寸 / -1 无初始化器 / 显式零）。
/// 尺寸约定（parser）：`-1` = 未指定（哨兵）、`0` = VLA 或显式零（靠
/// is_vla 区分）。不误伤：初始化器推断、VLA、形参退化（不经此检查）、
/// extern 不完整声明（调用方跳过）。
pub fn TypeChecker::check_array_dims_legality(
  self : TypeChecker,
  ty : @ast.Type,
  has_init_list : Bool,
  loc : @source.SourceLoc,
) -> Unit {
  match ty {
    Array(_, _, dims, _, is_vla, _) => {
      if is_vla {
        return // VLA 维度运行时求值，另有边界检查
      }
      let first = if dims.length() > 0 { dims[0] } else { -1 }
      if first < -1 {
        self.report_error(
          "数组大小不能为负数（\{first}）",
          loc,
          E2002_ExpectedArraySize,
        )
      } else if first == -1 && !has_init_list {
        self.report_error(
          "数组缺少数组大小：需要显式大小或初始化器来推断（int a[N]; 或 int a[] = {...};）",
          loc,
          E2002_ExpectedArraySize,
        )
      } else if first == 0 {
        // 显式零尺寸（含带初始化器——{1,2} 曾被静默推断成 2 元素数组）；
        // 零长度数组不是标准 C，教学子集不支持
        self.report_error(
          "数组大小不能为 0（零长度数组不在教学子集内）",
          loc,
          E2002_ExpectedArraySize,
        )
      }
    }
    _ => ()
  }
}

///|
/// W0-4：int→char 初始化器是否确定无损（字符常量 / char 值域内整常量）。
pub fn is_char_safe_initializer(expr : @ast.Expr) -> Bool {
  match expr {
    Literal(value, _, ty) =>
      ty.kind() is TK_Char || (value >= -128 && value <= 127)
    LongLiteral(value, _, _) => value >= -128 && value <= 127
    _ => false
  }
}
