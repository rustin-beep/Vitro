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
  line : Int32
  column : Int32
  code : Int32
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
  // #50 批①（2026-10-10）：static 全局首次声明行——E3059 前向序检查
  //（使用点早于任何声明 = 对齐 Clang use-before-declaration）
  static_global_decl_lines : Map[String, Int32]
  // #337（2026-10-28）：非 static 文件作用域全局的首次声明位置
  //（(line, column) 对 = 文本位置序——PR #344 审阅 P2-1 起含列：行号
  // 严格小于在单行程序失效，同行按列判前向）——函数体前向引用守卫
  // 判据（set 保持首值：extern/tentative 再声明不刷新，先行 extern/
  // tentative 条目给出可见性，对齐 C11 6.2.1p4 声明点语义；static 面
  // 走 static_global_decl_lines 的 E3059 通道，两表分治防双报）
  global_decl_lines : Map[String, (Int32, Int32)]
  // #331（2026-10-27）：文件作用域全局的首声明序（program.globals 数组
  // 首现下标 = 声明点序，C11 6.2.1p4）——初始化器前向引用守卫判据
  global_first_decl_idx : Map[String, Int32]
  // #331：当前正在检查初始化器的文件作用域声明下标（Pass 2.5 检查段
  // 逐 g 设置；函数体 Pass 4 语境为 None——局部声明点语义由 scope 栈
  // 天然保证，不进守卫）
  mut static_init_site_idx : Int32?
  structs : Map[String, StructSymbol]
  unions : Map[String, StructSymbol]
  // 作用域栈
  scopes : Array[Map[String, VarSymbol]]
  // 上下文标量（Rust 同名照搬——visitor 期间可变）
  mut current_func_return : @ast.Type?
  mut current_file : String
  mut loop_depth : Int32
  mut switch_depth : Int32
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
    static_global_decl_lines: Map([]),
    global_decl_lines: Map([]),
    global_first_decl_idx: Map([]),
    static_init_site_idx: None,
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
  // #145（2026-10-18）：前向声明（is_forward）与完整定义分轨——
  // ①重复前向合法（不覆盖既有条目）；②前向后完整定义=合法升级（旧
  // 形态前向被当零字段完整定义，后续定义误报 E3002）；③完整+完整
  // 仍 E3002（照旧）。
  for si in 0..<program.structs.length() {
    let s = program.structs[si]
    // #265/P1-5（审阅批 2026-10-23 改）：成员数组的 cast/sizeof 维数
    // 折叠**延迟**到全局符号+尺寸推断定型后统一跑（defer_refold_
    // members）——struct 注册期 lookup_var 扑空（sizeof g/sizeof g[0]
    // 的 g 未登记），旧即时折叠只覆盖纯 cast 面，sizeof 惯用语折不出
    // 维持 0 哨兵（type_size 算 4 + 下标越界 TRAP）
    if s.is_forward {
      if !self.structs.contains(s.name) {
        self.structs.set(s.name, { fields: [], is_complete: false, })
      }
      continue
    }
    match self.structs.get(s.name) {
      Some(existing) =>
        if existing.is_complete {
          self.report_error(
            "结构体 '\{s.name}' 重复定义",
            s.loc,
            E3002_StructRedeclared,
          )
        } else {
          // 前向 → 完整：合法升级
          self.structs.set(s.name, {
            fields: s.fields.map(f => (f.ty, f.name)),
            is_complete: true,
          })
        }
      None =>
        self.structs.set(s.name, {
          fields: s.fields.map(f => (f.ty, f.name)),
          is_complete: true,
        })
    }
    // #145 对抗补面：值成员类型须完整（clang "field has incomplete
    // type"——指针成员豁免〔check_type_complete 头注〕；StructField
    // 无 loc，用声明位置；自引用值成员由 E3072 环检测另行承载）
    match self.structs.get(s.name) {
      Some(sym) =>
        if sym.is_complete {
          for f in s.fields {
            self.check_type_complete(f.ty, s.loc)
          }
        }
      None => ()
    }
    // #157（2026-10-18，C23 §6.7.2.1p23 约束）：柔性数组成员（首维
    // 未知的数组成员 `int d[]`，dims[0] == -1）只允许出现在最后一个
    // 成员位且须有另一命名成员——非末位 / 孤立柔性均报 E3079（clang
    // "flexible array member is not at the end of struct" /
    // "flexible array member in otherwise empty struct"）
    for i, f in s.fields {
      if is_flexible_array_member(f.ty) &&
        (i != s.fields.length() - 1 || s.fields.length() < 2) {
        self.report_error(
          "柔性数组成员 '\{f.name}' 必须是结构体的最后一个成员且须有其他命名成员（C23 约束）",
          s.loc,
          E3079_FlexibleArrayInit,
        )
      }
    }
    // #174（2026-10-19，C11 §6.7.2.1p7 约束）：同一 struct 内成员名唯一
    //——clang/gcc 双 error "duplicate member"；旧零诊断误收（异类型重复
    // 同约束；typedef struct 匿名体与嵌套字段类型里的定义走同一注册路径）
    self.check_duplicate_member_names(s, "结构体")
  }
  for ui in 0..<program.unions.length() {
    let u = program.unions[ui]
    // #265/P1-5 同 struct：成员维数折叠延迟到 defer_refold_members
    if u.is_forward {
      if !self.unions.contains(u.name) {
        self.unions.set(u.name, { fields: [], is_complete: false, })
      }
      continue
    }
    match self.unions.get(u.name) {
      Some(existing) =>
        if existing.is_complete {
          self.report_error(
            "联合体 '\{u.name}' 重复定义",
            u.loc,
            E3002_StructRedeclared,
          )
        } else {
          self.unions.set(u.name, {
            fields: u.fields.map(f => (f.ty, f.name)),
            is_complete: true,
          })
        }
      None =>
        self.unions.set(u.name, {
          fields: u.fields.map(f => (f.ty, f.name)),
          is_complete: true,
        })
    }
    // #174 同约束（C11 §6.7.2.1p7 对 union 同样适用）
    self.check_duplicate_member_names(u, "联合体")
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
  // #145 连坐（对抗测试实锤）：净化 structs/unions 数组——同名完整
  // 定义存在时的前向条目**移除**。否则 codegen 逐条注册 struct_defs
  // 会用最后的零字段前向条目**反向覆盖**完整定义（`struct S{...};
  // struct S;` 后 struct 按值传参字段错位——min_f3 探针 1048572）。
  let cleaned_structs : Array[@ast.StructDecl] = []
  for s in program.structs {
    if s.is_forward {
      match self.structs.get(s.name) {
        Some(sym) =>
          if sym.is_complete {
            continue // 完整定义在册——前向条目出列
          }
        None => ()
      }
    }
    cleaned_structs.push(s)
  }
  program.structs.clear()
  for s in cleaned_structs {
    program.structs.push(s)
  }
  let cleaned_unions : Array[@ast.StructDecl] = []
  for u in program.unions {
    if u.is_forward {
      match self.unions.get(u.name) {
        Some(sym) => if sym.is_complete { continue }
        None => ()
      }
    }
    cleaned_unions.push(u)
  }
  program.unions.clear()
  for u in cleaned_unions {
    program.unions.push(u)
  }
  // Pass 2: 函数签名注册
  // #265 注：形参数组在 parser 层已 decay 成 Pointer(subscript_type)——
  // cast 维度的 VLA 误判由 subscript_type 的 is_vla 传导修正收口（ast
  // 包），此处无需再折（Pointer 的 is_vla 恒 false，折臂永不进）。
  for f in program.funcs {
    let new_sym : FuncSymbol = {
      return_type: f.return_type,
      param_types: f.params.map(p => p.ty),
      is_variadic: f.is_variadic,
      param_defaults: f.params.map(p => p.default),
      is_definition: f.body is Some(_),
      first_decl_line: f.loc.line,
      first_decl_col: f.loc.column,
    }
    if f.is_static {
      match self.static_func_sigs.get(f.name) {
        Some(existing) =>
          if !@ast.type_eq(
              strip_top_const(existing.return_type),
              strip_top_const(new_sym.return_type),
            ) ||
            !params_eq(existing.param_types, new_sym.param_types) {
            self.report_error(
              "函数 '\{f.name}' 的声明与之前定义签名不一致",
              f.loc,
              E3003_FuncRedeclared,
            )
          } else if existing.is_definition && new_sym.is_definition {
            // #50 批①（2026-10-10）：同签名双完整定义 = 重定义——
            // 对齐 Clang "redefinition of function"（默认 error；原型
            // 声明 + 定义合法不报）
            self.report_error(
              "函数 '\{f.name}' 重复定义",
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
          if !@ast.type_eq(
              strip_top_const(existing.return_type),
              strip_top_const(new_sym.return_type),
            ) ||
            !params_eq(existing.param_types, new_sym.param_types) {
            self.report_error(
              "函数 '\{f.name}' 的声明与之前定义签名不一致",
              f.loc,
              E3003_FuncRedeclared,
            )
          } else if existing.is_definition && new_sym.is_definition {
            // #50 批①：同上——非 static 函数同款重定义检查
            self.report_error(
              "函数 '\{f.name}' 重复定义",
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
  // #337（2026-10-28）：非 static 全局首声明位置表（PR #344 审阅 P2-1
  // 起 (line, column) 对）——建表先于 auto/typeof 预解析（预解析语境
  // static_init_site_idx 为 None，守卫激活面包含它）与 Pass 3/4 函数体
  // 检查；set 保持首值，extern/tentative 先行条目给出可见性（clang
  // 口径：首声明点即可见）
  for g in program.globals {
    if !g.is_static && !self.global_decl_lines.contains(g.name) {
      self.global_decl_lines.set(g.name, (g.loc.line, g.loc.column))
    }
  }
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
    // #182 D-2（2026-10-19，C11 §6.2.7p1）：文件作用域内函数名与变量名
    // 同名 = 不同类符号重定义——clang "redefinition of 'g' as different
    // kind of symbol"（Pass 2 函数注册先行，此处查交叉；static 函数在
    // static_func_sigs、普通函数在 funcs——同文件普通标识符命名空间
    // 合一，两表都查且不分 static 侧别）
    if self.funcs.contains(g.name) || self.static_func_sigs.contains(g.name) {
      self.report_error(
        "变量 '\{g.name}' 与已声明的函数同名——同一作用域内函数名与变量名不能重复（C 的普通标识符命名空间合一）",
        g.loc,
        E3003_FuncRedeclared,
      )
    }
    // #331：首声明序登记（保持首值——tentative/extern 再声明不刷新，
    // 对齐 static_global_decl_lines 的 #50 首值模式）
    if !self.global_first_decl_idx.contains(g.name) {
      self.global_first_decl_idx.set(g.name, i)
    }
    self.declare_var(
      g.name,
      g.ty,
      is_global=true,
      is_extern=g.is_extern,
      is_static=g.is_static,
      is_tentative=g.init is None && !g.is_extern,
      loc=g.loc,
    )
    if g.is_static {
      match self.static_global_files.get(g.name) {
        Some(files) => files.push(g.source_file)
        None => self.static_global_files.set(g.name, [g.source_file])
      }
      // #50 批①：首次登记行（set 保持首值——原型/重复声明不刷新）。
      // PR #344 审阅 P2-2（2026-10-28）首值让位：名字的首声明是**更早
      // 的非 static 条目**（`int t; … static int t = 5;` 的 s8 形态——
      // clang 零诊断，后随 static 生效但可见性锚在首声明）时，本 static
      // 条目不写表——否则 E3059 前向判据锚到后随条目、对首声明后的
      // 引用歪报「声明之前被使用」。判定用 #331 的 global_first_decl_idx
      //（含全部 globals 的首现下标）：本条不是首声明即让位。
      if !self.static_global_decl_lines.contains(g.name) &&
        self.global_first_decl_idx.get(g.name) == Some(i) {
        self.static_global_decl_lines.set(g.name, g.loc.line)
      }
    }
  }
  // #265/P1-5（审阅批 2026-10-23）：struct/union 成员的 cast/sizeof 维数
  // 折叠延迟点——全局符号登记与数组尺寸推断均定型（sizeof g/sizeof g[0]
  // 的 lookup_var 命中真类型），折后回写 program 与 structs/unions 符号
  // 表（is_complete 保持）；注册期即时折叠只覆盖纯 cast 面（sizeof 折
  // 不出 ⇒ 维持 0 哨兵、type_size 4、下标越界 TRAP——审阅 p8 实锤）
  for i in 0..<program.globals.length() {
    let g = program.globals[i]
    // #331：进入本 g 的初始化器检查语境（前向引用守卫激活面——
    // diagnose_static_init 的地址常量族按首声明序判定）
    self.static_init_site_idx = Some(i)
    // #265（2026-10-22）：cast/sizeof 维数误判 VLA 的常量二次折叠——
    // 折在**尺寸推断循环内、逐个声明检查前**（sizeof 惯用法引用的先行
    // 全局此时已推断回写符号表）；折出后回写 program + 符号表，codegen
    // 的「全局不支持 VLA」与传参 E3038 一并解除
    let refolded = self.refold_vla_const_dims(g.ty)
    if refolded is Array(_, _, _, _, false, _) &&
      g.ty is Array(_, _, _, _, true, _) {
      program.globals[i] = { ..g, ty: refolded, }
      self.update_var_type(g.name, refolded)
    }
    let g = program.globals[i]
    // U1#12：全局数组尺寸合法性——extern 不完整声明（extern int g[];）
    // 是合法的，跳过；无初始化器的 `int a[];` 全局定义必须报错
    if g.ty.is_array() && !g.is_extern {
      let has_init_list = g.init is Some(InitList(_, _, _)) ||
        g.init is Some(StringLiteral(_, _, _))
      self.check_array_dims_legality(g.ty, has_init_list, g.loc)
    }
    // #145：全局值形态完整性——extern 声明豁免（`extern struct S x;`
    // 合法 tentative 声明，C11 §6.9.2p3；定义形态才要求完整）
    if !g.is_extern {
      self.check_type_complete(g.ty, g.loc)
    }
    if g.init is Some(init) {
      if g.ty.is_array() {
        let (new_ty, new_init) = self.check_array_initializer(g.ty, init, g.loc)
        // P4：`char g[] = "str"` 的尺寸推断发生在 declare_var 之后——
        // 回写符号表，否则 sizeof(g) 用推断前快照恒 1
        self.update_var_type(g.name, new_ty)
        // #142/#151：静态初始化器常量折叠（元素级）+ 非常量诊断
        let folded = self.fold_static_aggregate(new_ty, new_init)
        program.globals[i] = { ..g, ty: new_ty, init: Some(folded), }
      } else if (g.ty.kind() is TK_Struct || g.ty.kind() is TK_Union) &&
        init is InitList(_, _, _) {
        let new_init = self.check_struct_initializer(g.ty, init, g.loc)
        let folded = self.fold_static_aggregate(g.ty, new_init)
        program.globals[i] = { ..g, init: Some(folded), }
      } else {
        // 深挖批（2026-10-18，C11 6.7.9p11）：全局标量的大括号包裹解包
        //（`int g = {42}` ≡ 裸形态；多余元素 W3005 取首——clang -Wexcess
        // 口径）。聚合/数组已在前两分支分流；解包改写存回后走既有
        // resolve/assignable/静态折叠链
        let init = match self.unwrap_scalar_braces(init, g.loc) {
          Some(u) => {
            program.globals[i] = { ..g, init: Some(u), }
            u
          }
          None => init
        }
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
        let g_init_expr : @ast.Expr? = g_now.init
        let g_assign_ok : Bool = match g_init_expr {
          Some(ie) =>
            self.check_assignable(new_ty, init_type, g.loc, value_expr=ie)
          None => self.check_assignable(new_ty, init_type, g.loc)
        }
        if !g_assign_ok {
          self.report_error(
            "类型不匹配：无法将 '\{init_type.to_c_string()}' 赋值给 '\{new_ty.to_c_string()}'",
            g.loc,
            E3004_TypeMismatch,
          )
        }
        // #142/#151：标量静态初始化器折叠（成功→字面量交 codegen 既有
        // 路径；失败→E3075 诊断）
        match program.globals[i].init {
          Some(ie_now) =>
            program.globals[i] = {
              ..program.globals[i],
              init: Some(self.fold_static_init(new_ty, ie_now)),
            }
          None => ()
        }
      }
    }
  }
  // #331：退出文件作用域初始化器检查语境（后续 Pass 4 函数体内 static
  // 走同一 fold/diagnose 链——site 置 None，局部声明点语义由 scope 栈
  // 天然保证，不进守卫）
  self.static_init_site_idx = None
  // #265/P1-5（审阅批 2026-10-23）：defer 移位二段——必须在全局尺寸
  // 推断循环**之后**（`static const char *TIPS[] = {...}` 的维数推断
  // 发生在该循环，之前跑 lookup_var 拿 [-1] 未定型 → sizeof 惯用法
  // 折不出〔tipsize 8 vs 32 实锤〕）
  self.defer_refold_members(program)
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
    // issue #23 销案（2026-10-06）：形参**顶层** const 差异不构成签名
    // 不一致（C11 §6.7.6.3(15)——顶层限定符不参与函数类型兼容；两侧都
    // 剥再比）。嵌套 const（const char* 的 pointee const）参与比较不动
    if !@ast.type_eq(strip_top_const(a[i]), strip_top_const(b[i])) {
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
/// VLA 维度子树扫描（审阅批 P2，2026-10-11）：收集维度表达式全部
/// Identifier 叶并对未声明者报 E3023（容器类变体递归——Binary/Unary/
/// Ternary/Cast/Index/Call 实参；Call 的函数名是 String 非 Expr 节点，
/// 未声明函数面由调用检查承接；Literal/Sizeof 等无标识符叶直接跳过）。
/// 此前判据绑顶层 `Identifier` 形态，`int a[N + 1];`（顶层 Binary）
/// 绕过、静默漏到 codegen 无码错误；clang 两形态同报一条。
fn TypeChecker::report_undeclared_dim_idents(
  self : TypeChecker,
  expr : @ast.Expr,
) -> Unit {
  match expr {
    Identifier(name, dloc, _) =>
      if self.lookup_var(name) is None && !self.funcs.contains(name) {
        self.report_error(
          "未定义的标识符 '\{name}'（数组维度须为常量表达式或已声明的变量）",
          dloc,
          E3023_UndeclaredVar,
        )
      }
    Binary(_, l, r, _, _) => {
      self.report_undeclared_dim_idents(l)
      self.report_undeclared_dim_idents(r)
    }
    Unary(_, operand, _, _) => self.report_undeclared_dim_idents(operand)
    Ternary(c, t, f, _, _) => {
      self.report_undeclared_dim_idents(c)
      self.report_undeclared_dim_idents(t)
      self.report_undeclared_dim_idents(f)
    }
    Cast(inner, _, _, _) => self.report_undeclared_dim_idents(inner)
    Index(base, idx, _, _) => {
      self.report_undeclared_dim_idents(base)
      self.report_undeclared_dim_idents(idx)
    }
    Call(_, args, _, _) =>
      for a in args {
        self.report_undeclared_dim_idents(a)
      }
    _ => ()
  }
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
    Array(_, _, dims, _, is_vla, vla_dims) => {
      if is_vla {
        // #70 第一步（#64 v6 尾巴，2026-10-11）：VLA 维度表达式里的**裸
        // 未声明标识符**（宏漏 define / 拼写错——const_int_of 折不出的
        // Identifier）报 E3023 而非静默走到 codegen 判「不支持 VLA」——
        // 真维度（已声明变量）不报，维持运行时求值路径。
        // 审阅批 P2 修正（2026-10-11）：判据不绑顶层节点形态——按语义
        // 扫**子树**全部 Identifier 叶（`int a[N + 1];` 顶层 Binary 此前
        // 绕过判据，静默漏到 codegen 无码错误；clang 两形态同报一条）
        for dim_expr in vla_dims {
          self.report_undeclared_dim_idents(dim_expr)
        }
        return // 其余 VLA 维度运行时求值，另有边界检查
      }
      let first = if dims.length() > 0 { dims[0] } else { -1 }
      // #182 D-3（2026-10-19，C11 §6.7.6.2p1 约束）：负尺寸是约束违反，
      // clang/gcc 双 error "array size is negative"——旧 W2002 警告误收；
      // 无尺寸且无初始化器（含 `int a[-1]` 显式负——dims 哨兵与 [] 同值
      // 不可分，两形态 clang 均 error）同升 error。零尺寸维持 W（GNU
      // 零长数组扩展域，gcc 默认仅警告）
      if first < -1 {
        self.report_error(
          "数组大小不能为负数（\{first}）",
          loc,
          E3081_NegativeArraySize,
        )
      } else if first == -1 && !has_init_list {
        self.report_error(
          "数组缺少数组大小：需要显式大小或初始化器来推断（int a[N]; 或 int a[] = {...};）",
          loc,
          E3081_NegativeArraySize,
        )
      } else if first == 0 {
        // 显式零尺寸（含带初始化器——{1,2} 曾被静默推断成 2 元素数组）；
        // 零长度数组不是标准 C，教学子集不支持
        self.report_warning(
          "数组大小不能为 0（零长度数组不在教学子集内）",
          loc,
          W2002_ExpectedArraySize,
        )
      }
    }
    _ => ()
  }
}

///|
/// W0-4：int→char 初始化器是否确定无损（字符常量 / char 值域内整常量）。
fn is_char_safe_initializer(expr : @ast.Expr) -> Bool {
  match expr {
    Literal(value, _, ty) =>
      ty.kind() is TK_Char || (value >= -128 && value <= 127)
    LongLiteral(value, _, _) => value >= -128 && value <= 127
    _ => false
  }
}

///|
/// #174（2026-10-19）：同一 struct/union 内成员名唯一性检查（C11
/// §6.7.2.1p7 约束）。插入序去重报首个重复对（clang "duplicate member"
/// 对齐：报重复名本身；异类型重复同约束）。kind_label 区分结构体/联合体
/// 文案。
fn TypeChecker::check_duplicate_member_names(
  self : TypeChecker,
  decl : @ast.StructDecl,
  kind_label : String,
) -> Unit {
  let seen : Set[String] = Set([])
  for f in decl.fields {
    // #249（2026-10-22，C11 6.7.2.1p13）：匿名成员（无声明器，name 空）
    // 不参与重名判——多个匿名 union/struct 成员合法（内部成员经提升
    // 访问）；旧空名互撞误报 E3080「成员 '' 重复定义」。提升成员与
    // 外层成员的重名约束检查（p13 constraint）另登记（教学域收窄）
    if f.name == "" {
      continue
    }
    if seen.contains(f.name) {
      self.report_error(
        "\{kind_label} '\{decl.name}' 的成员 '\{f.name}' 重复定义——同一结构体内的成员名必须唯一",
        decl.loc,
        E3080_StructDuplicateMember,
      )
    } else {
      seen.add(f.name)
    }
  }
}
