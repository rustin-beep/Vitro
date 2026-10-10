///|
/// Vitro 语法分析器（S3 片）——从 token 流解析 AST。
///
/// 照搬 Rust oracle `native/crates/vitro_parser/src/lib.rs`（4,879 行十文件）
/// 的解析语义；**防护形态不复刻**（勘察 parser 报告 M1，第一阶段计划 P1）：
///
/// 1. **深度统一入口**：Rust 的共享计数器字段 + 8 处壳挂点
///    （statement/assign/ternary/unary/primary/init_list/abstract_declarator/
///    param_list）改为显式 `depth` 参数沿调用链传递——计数语义与 Rust
///    **同构**（壳函数检查 `depth >= MAX_PARSE_DEPTH` 对应 Rust 先检
///    后增；body 与下层传 `depth+1`；offsetof/sizeof/alignof 等类型
///    通道透传 body depth——F1 教训：类型系统只强制"传了 depth"，
///    不强制"取值正确"，形参硬编码 0 会静默失效，故同构性以阈值锚
///    `parser_diff --threshold` 机判，不靠声明形态保证）。
/// 2. **回滚快照全量**：Rust 三元快照（pos/errors/anonymous_structs）+
///    三处手工补 typedef_names——本实现单一 Rollback 含全部七类解析期
///    副作用（typedef_names/template_names 不可变结构共享快照 + pos/
///    errors/anon/current_class 长度 + next_lambda_id），A5 回滚面缺口
///    结构性消除。可观测等价：手工补的三处含在 restore 内；sizeof 处
///    的差异按 A5 分析不可观测（污染值与首次写入同值 + 合法 C 不可达）。
/// 3. **活性内部断言**：主循环零推进记账（`stall_count`），常规路径
///    不改变恢复控制流（照搬 Rust 三层活性约定）+ G1 熔断下界（
///    `MAX_STALL_ROUNDS` 超限出 E1006 并强推一个 token——synchronize
///    在同步 token 上可零推进的 Y5 病灶由此有终止性保证），防线侧经
///    dump 出口观测。
///
/// 病态深度预算四常量照搬（P1 后 Rust 现值）：MAX_PARSE_DEPTH=256 /
/// MAX_AST_DEPTH=512 / MAX_DECLARATOR_SUFFIX=1250 / MAX_TYPE_DEPTH=1250。
pub(all) struct ParseError {
  message : String
  line : Int
  column : Int
  code : Int
} derive(Eq, @debug.Debug)

///|
pub extend ParseError with Debug::{to_repr}

///|
pub extend ParseError with Eq::{not_equal, equal}

///|
/// 解析结果（单值返回，S2 LexResult 同款惯例；对应 Rust
/// `parse() -> (Option<ProgramNode>, Vec<ParseError>)`）。
pub(all) struct ParseResult {
  program : @ast.ProgramNode?
  errors : Array[ParseError]
  /// 活性内部断言计数：主循环零推进次数（生产零消费；防线侧 dump 观测，
  /// 勘察 6-3 的 GC 语言观测义务——故障信号从"内存涨"弱化为"无诊断"，
  /// 必须显式记账）
  stall_count : Int
}

///|
/// 声明符节点树（C 螺旋规则中间表示；照搬 Rust `DeclaratorNode`）。
pub enum DeclaratorNode {
  Base
  Pointer(DeclaratorNode)
  Reference(DeclaratorNode, Bool) // is_const
  RValueRef(DeclaratorNode)
  Array(DeclaratorNode, @ast.Expr?) // size_expr
  Function(DeclaratorNode, Array[@ast.Param], Bool) // is_variadic
} derive(@debug.Debug)

///|
pub extend DeclaratorNode with Debug::{to_repr}

///|
priv enum DeclaratorSuffix {
  ArrSuffix(@ast.Expr?) // size_expr
  FuncSuffix(Array[@ast.Param], Bool) // is_variadic
}

///|
/// 声明符复杂度保险丝组（照搬 Rust：paren_depth/ptr_count/suffix_count/
/// cross_count——P1 后 suffix_count 已接上比较，非死字段）。
priv struct DeclaratorGuard {
  mut paren_depth : Int
  mut ptr_count : Int
  mut suffix_count : Int
  mut cross_count : Int
}

///|
fn DeclaratorGuard::init() -> DeclaratorGuard {
  { paren_depth: 0, ptr_count: 0, suffix_count: 0, cross_count: 0, }
}

///|
fn node_cross_count(node : DeclaratorNode) -> Int {
  match node {
    Base => 0
    Pointer(inner) | Reference(inner, _) | RValueRef(inner) => {
      let add = match inner {
        Array(_, _) | Function(_, _, _) => 1
        _ => 0
      }
      node_cross_count(inner) + add
    }
    Array(inner, _) | Function(inner, _, _) => node_cross_count(inner)
  }
}

///|
/// 统一回滚点——**七字段全量快照**（形态改造，见包注释 2）。
/// typedef_names / template_names 为可变哈希结构，快照 = 整表拷贝
///（教学程序的符号表小，O(n) 拷贝可接受；回滚即换引用）。
priv struct Rollback {
  pos : Int
  errors_len : Int
  anon_len : Int
  /// 匿名/嵌套 union 回滚水位（issue #7）
  anon_u_len : Int
  /// 已解析聚合表回滚水位（issue #13）
  agg_len : Int
  /// 变量类型表回滚水位
  var_types_len : Int
  typedef_names : Map[String, @ast.Type]
  template_names : Set[String]
  current_class_len : Int
  next_lambda_id : Int
}

///|
/// 递归深度上限（照搬 Rust 256；勘察 7-S1 实测 wasm-gc 21 帧瀑布 854 层，
/// 余量充足）。计数口径 = 活跃壳数（每层括号嵌套 4 计数：assign+ternary+
/// unary+primary 壳），与 Rust 共享计数器同构——阈值样本（62/63 层括号）
/// 的触发边界逐位一致是 E3 对拍前提。
const MAX_PARSE_DEPTH : Int = 256

///|
/// 后置 AST 深度预算（照搬 Rust 512；typeck/快照等递归遍历安全上界）。
const MAX_AST_DEPTH : Int = 512

///|
/// 声明符后缀（数组/函数）链式层级上限（照搬 Rust P1 值 1250：release
/// 1200 层存活 / 1300 层崩溃边界之下的防护位）。
const MAX_DECLARATOR_SUFFIX : Int = 1250

///|
/// 类型树深度预算（照搬 Rust P1 值 1250；深 Type 对 MAX_AST_DEPTH 隐身
/// 的后置兜底）。
const MAX_TYPE_DEPTH : Int = 1250

///|
/// 声明符指针前缀上限（照搬 Rust 32）。
const MAX_DECLARATOR_PTR : Int = 32

///|
/// 零推进熔断轮数（G1 守卫，MoonBit 新增——Rust 无）：零进度保护三层
/// 约定（分支推进 / pos==checkpoint 检查 / 顶层兜底 advance）照搬自
/// Rust 且勘察 J5 实测收敛，但 `synchronize` 在同步 token 上可零推进
/// （Y5 病灶），理论死循环窗口仍在——熔断保证终止性下界：超限即出
/// E1006 诊断并强推一个 token（真死循环可观测，不挂死）。597 真实
/// 语料 stall=0 恒不触发。
const MAX_STALL_ROUNDS : Int = 1000

///|
/// G1 熔断：零推进超限——出诊断 + 强推一个 token，保证解析必然前进。
/// 返回 true 表示本轮已强制推进（调用方跳过常规同步）。
fn Parser::stall_breaker(self : Parser) -> Bool {
  if self.stall_count <= MAX_STALL_ROUNDS || self.is_at_end() {
    return false
  }
  let cur = self.current()
  self.errors.push({
    message: "解析零推进停滞（\{self.stall_count} 轮同步未前进）——强制跳过 token 保证终止",
    line: cur.loc.line,
    column: cur.loc.column,
    code: @diag.ErrorCode::E1006_UnsupportedFeature.code(),
  })
  ignore(self.advance())
  true
}

///|
/// 深度超限中性占位（照搬 Rust `Expr::default()`：Literal 0 + 默认坐标 +
/// Void）。
fn default_expr() -> @ast.Expr {
  @ast.Expr::Literal(0, @source.SourceLoc::default(), @ast.Type::void_type())
}

///|
priv struct Parser {
  tokens : Array[@token.Token]
  errors : Array[ParseError]
  mut typedef_names : Map[String, @ast.Type]
  mut template_names : Set[String]
  mut pos : Int
  anonymous_structs : Array[@ast.StructDecl]
  /// 匿名/嵌套 union 声明收集（issue #7——union 布局语义灌 program.unions）
  anonymous_unions : Array[@ast.StructDecl]
  /// program 引用（issue #15：嵌套 enum 成员位置的枚举常量注册需要
  /// program——parse_program 开头注入；None = 单测直接构造 Parser 场景）
  mut program_sink : @ast.ProgramNode?
  /// 已解析聚合定义表（issue #13，2026-10-06）：parse_struct_body 单点
  /// 收口追加（tag/匿名/嵌套/typedef 全路径）——static_assert 常量求值
  /// 的 sizeof(struct/union) 折叠源（旧空表致 sizeof(聚合) 恒 None →
  /// E1006 假阳性）。追加式 + 回滚长度水位（Map 无快照语义）
  parsed_aggregates : Array[(String, Bool, Array[@ast.StructField])]
  /// Bool = is_union

  /// 已解析变量类型表（issue #13 数组形态）：声明点收口（全局+局部）。
  /// 审阅 P1-1 修正（2026-10-07）：分块栈形态——每个 block/函数体 push
  /// 边界，离开时 truncate 回水位（旧单表 append-only 让内层同名声明
  /// 污染外层——`{ double x; }` 后外层 sizeof(x) 错取 double）。快照 =
  /// 全表合并（内层遮蔽外层由后写覆盖语义天然成立），作用域语义由
  /// block 边界的 truncate 保证
  parsed_var_types : Array[(String, @ast.Type)]
  /// 变量类型表的 block 边界水位栈（enter/leave block 配对）
  var_type_marks : Array[Int]
  is_cpp_mode : Bool
  mut next_lambda_id : Int
  /// C++ 嵌套类解析上下文：当前外层类名栈
  current_class : Array[String]
  /// 活性记账：主循环零推进次数（推进控制流照搬 Rust，此处仅观测）
  mut stall_count : Int
}

///|
fn Parser::save(self : Parser) -> Rollback {
  {
    pos: self.pos,
    errors_len: self.errors.length(),
    anon_len: self.anonymous_structs.length(),
    anon_u_len: self.anonymous_unions.length(),
    agg_len: self.parsed_aggregates.length(),
    var_types_len: self.parsed_var_types.length(),
    typedef_names: self.typedef_names.copy(),
    template_names: self.template_names.copy(),
    current_class_len: self.current_class.length(),
    next_lambda_id: self.next_lambda_id,
  }
}

///|
fn Parser::restore(self : Parser, rb : Rollback) -> Unit {
  self.pos = rb.pos
  self.errors.truncate(rb.errors_len)
  self.anonymous_structs.truncate(rb.anon_len)
  self.anonymous_unions.truncate(rb.anon_u_len)
  self.parsed_aggregates.truncate(rb.agg_len)
  self.parsed_var_types.truncate(rb.var_types_len)
  self.typedef_names = rb.typedef_names
  self.template_names = rb.template_names
  self.current_class.truncate(rb.current_class_len)
  self.next_lambda_id = rb.next_lambda_id
}

///|
/// 构造解析器（照搬 Rust `with_mode`：预定义 FILE 类型 + C++ 内置容器）。
fn Parser::with_mode(
  tokens : Array[@token.Token],
  is_cpp_mode : Bool,
) -> Parser {
  let typedef_names : Map[String, @ast.Type] = Map([])
  let template_names : Set[String] = Set([])
  // 预定义 FILE 类型（stdio.h 中的不透明结构体指针）
  typedef_names.set("FILE", @ast.Type::void_type())
  // 预注册 C++ 内置容器类型名
  if is_cpp_mode {
    register_cpp_builtin_types(typedef_names, template_names)
  }
  {
    tokens,
    errors: [],
    typedef_names,
    template_names,
    pos: 0,
    anonymous_structs: [],
    anonymous_unions: [],
    program_sink: None,
    parsed_aggregates: [],
    parsed_var_types: [],
    var_type_marks: [],
    is_cpp_mode,
    next_lambda_id: 0,
    current_class: [],
    stall_count: 0,
  }
}

///|
/// 壳挂点深度超限处理（照搬 Rust `enter_depth` 失败分支：记录 E1006 并
/// 跳到文件尾——过深嵌套已无恢复价值，跳到尾部让外层循环自然收敛）。
fn Parser::depth_exceeded(self : Parser, what : String) -> Unit {
  let cur = self.current()
  self.errors.push({
    message: "\{what}嵌套过深（超过 \{MAX_PARSE_DEPTH} 层），已停止解析",
    line: cur.loc.line,
    column: cur.loc.column,
    code: @diag.ErrorCode::E1006_UnsupportedFeature.code(),
  })
  let n = self.tokens.length()
  if n > 0 {
    self.pos = n - 1
  }
}

///|
/// 解析入口（对应 Rust `Parser::parse`）：token 流 → (ProgramNode?, errors)。
/// 后置双预算（AST 深度 512 / 类型深度 1250）超限返回 None + E1006（照搬；
/// Rust 的 `mem::forget` 防 Drop 溢出在 GC 下不需要——勘察 7-S7）。
/// （F-2 终局：cpp_mode 参数已剔除——砍 C++ 后 C 输入是唯一形态；
/// C++ 分支代码保留为死路径等 S9 裁定，2026-09-21 收尾批，架构报告
/// 待办①"parser 未发布是最后的免费时机"）
pub fn parse(tokens : Array[@token.Token]) -> ParseResult {
  let p = Parser::with_mode(tokens, false)
  let prog = match p.parse_program() {
    Some(pr) => {
      for d in p.anonymous_structs {
        pr.structs.push(d)
      }
      for d in p.anonymous_unions {
        pr.unions.push(d)
      }
      pr
    }
    None =>
      return { program: None, errors: p.errors, stall_count: p.stall_count, }
  }
  // 后置 AST 深度预算（Expr/Stmt 面）
  match program_max_depth(prog) {
    Some(d) =>
      if d > MAX_AST_DEPTH {
        p.errors.push({
          message: "AST 嵌套深度 \{d} 超过预算 \{MAX_AST_DEPTH}：过深的表达式/初始化链会使后续处理栈溢出，请拆分表达式",
          line: 1,
          column: 1,
          code: @diag.ErrorCode::E1006_UnsupportedFeature.code(),
        })
        return { program: None, errors: p.errors, stall_count: p.stall_count, }
      }
    None => ()
  }
  // 类型深度预算（P1：深 Type 对上面的 Expr/Stmt 预算隐身）
  let tmax = program_max_type_depth(prog)
  if tmax > MAX_TYPE_DEPTH {
    p.errors.push({
      message: "类型嵌套深度 \{tmax} 超过预算 \{MAX_TYPE_DEPTH}：过深的类型链（数组后缀/typedef 链）会使后续处理栈溢出",
      line: 1,
      column: 1,
      code: @diag.ErrorCode::E1006_UnsupportedFeature.code(),
    })
    return { program: None, errors: p.errors, stall_count: p.stall_count, }
  }
  { program: Some(prog), errors: p.errors, stall_count: p.stall_count, }
}

// =========================================================================
// 深度测量（照搬 lib.rs 后置预算的测量面；ast 包四函数为迭代显式栈实现）
// =========================================================================

///|
fn program_max_depth(prog : @ast.ProgramNode) -> Int? {
  let mut max = 0
  for g in prog.globals {
    match g.init {
      Some(init) => {
        let d = @ast.expr_depth(init)
        if d > max {
          max = d
        }
      }
      None => ()
    }
  }
  for f in prog.funcs {
    match f.body {
      Some(body) => {
        let d = @ast.stmt_depth(body)
        if d > max {
          max = d
        }
      }
      None => ()
    }
  }
  if max == 0 {
    None
  } else {
    Some(max)
  }
}

///|
fn program_max_type_depth(prog : @ast.ProgramNode) -> Int {
  fn acc(t : @ast.Type, max : Int) -> Int {
    let d = @ast.type_depth(t)
    if d > max {
      d
    } else {
      max
    }
  }
  fn acc_stmt_type(s : @ast.Stmt, max : Int) -> Int {
    let d = @ast.stmt_type_depth(s)
    if d > max {
      d
    } else {
      max
    }
  }
  fn acc_body(b : @ast.Stmt?, max : Int) -> Int {
    match b {
      Some(s) => acc_stmt_type(s, max)
      None => max
    }
  }
  let mut max = 0
  for g in prog.globals {
    max = acc(g.ty, max)
  }
  for sd in prog.structs {
    for f in sd.fields {
      max = acc(f.ty, max)
    }
  }
  for sd in prog.unions {
    for f in sd.fields {
      max = acc(f.ty, max)
    }
  }
  // 嵌套类用显式工作栈遍历（测量器自身不递归，同 Rust depth.rs 纪律）
  let class_stack : Array[@ast.ClassDecl] = []
  for c in prog.classes {
    class_stack.push(c)
  }
  while class_stack.length() > 0 {
    let c = class_stack.remove(class_stack.length() - 1)
    for m in c.members {
      match m {
        Field(_, ty, _, _) => max = acc(ty, max)
        Method(_, ret, params, body, _, _, _, _) => {
          max = acc(ret, max)
          for p in params {
            max = acc(p.ty, max)
          }
          max = acc_body(body, max)
        }
        Constructor(params, body, _, _, _) => {
          for p in params {
            max = acc(p.ty, max)
          }
          max = acc_body(body, max)
        }
        Destructor(body, _, _) => max = acc_body(body, max)
        NestedClass(decl, _) => class_stack.push(decl)
        NestedStruct(decl, _) =>
          for f in decl.fields {
            max = acc(f.ty, max)
          }
      }
    }
  }
  for f in prog.funcs {
    max = acc(f.return_type, max)
    for p in f.params {
      max = acc(p.ty, max)
    }
    max = acc_body(f.body, max)
  }
  max
}

// =========================================================================
// Token helpers（照搬 lib.rs 访问原语；越界哨兵 = Eof/-1/-1 语义）
// =========================================================================

///|
fn eof_token() -> @token.Token {
  {
    ty: Eof,
    text: "",
    loc: { line: -1, column: -1, file_id: 0, },
    byte_off: -1,
    real_line: -1,
  }
}

///|
fn Parser::peek(self : Parser, offset : Int) -> @token.Token {
  if self.pos + offset >= self.tokens.length() {
    return eof_token()
  }
  self.tokens[self.pos + offset]
}

///|
fn Parser::current(self : Parser) -> @token.Token {
  self.peek(0)
}

///|
fn Parser::previous(self : Parser) -> @token.Token {
  if self.pos == 0 {
    return self.peek(0)
  }
  self.tokens[self.pos - 1]
}

///|
fn Parser::check(self : Parser, ty : @token.TokenType) -> Bool {
  if self.is_at_end() {
    return false
  }
  self.current().ty == ty
}

///|
fn Parser::is_at_end(self : Parser) -> Bool {
  self.current().ty == Eof
}

///|
fn Parser::advance(self : Parser) -> @token.Token {
  if !self.is_at_end() {
    self.pos += 1
  }
  if self.pos == 0 {
    return self.peek(0)
  }
  self.tokens[self.pos - 1]
}

///|
fn Parser::match_token(self : Parser, ty : @token.TokenType) -> Bool {
  if self.check(ty) {
    ignore(self.advance())
    true
  } else {
    false
  }
}

///|
fn Parser::consume(
  self : Parser,
  ty : @token.TokenType,
  msg : String,
) -> @token.Token {
  if self.check(ty) {
    return self.advance()
  }
  let code = match ty {
    RBrace => @diag.ErrorCode::E2006_ExpectedClosingBrace
    RParen => @diag.ErrorCode::E2007_ExpectedClosingParen
    RBracket => @diag.ErrorCode::E2008_ExpectedClosingBracket
    _ => @diag.ErrorCode::E2005_ExpectedSemicolon
  }
  // 缺分号报在 previous() 位置（分号本应在处），其余报在 current()——
  // E7 隐性口径，E2 位置列覆盖
  let cur = self.current()
  let prev = self.previous()
  let tmp : (Int, Int) = if ty == Semicolon && self.pos > 0 {
    (prev.loc.line, prev.loc.column)
  } else {
    (cur.loc.line, cur.loc.column)
  }
  self.errors.push({
    message: msg,
    line: tmp.0,
    column: tmp.1,
    code: code.code(),
  })
  // 自动恢复：根据缺失的闭合符号推断恢复集合，减少级联错误
  let recovery : Array[@token.TokenType] = match ty {
    RParen => [RParen, Semicolon]
    RBrace => [RBrace, Semicolon]
    RBracket => [RBracket, Semicolon]
    _ => [Semicolon]
  }
  self.synchronize(recovery)
  self.peek(0)
}

///|
/// 通用同步（照搬：跳到恢复集合中的 token / 语句边界；previous 是分号
/// 则停——可零推进，外层循环兜底是活性三层约定之二三层）。
fn Parser::synchronize(
  self : Parser,
  recovery_set : Array[@token.TokenType],
) -> Unit {
  while !self.is_at_end() {
    let cur = self.current().ty
    if recovery_set.contains(cur) {
      return
    }
    if self.previous().ty == Semicolon {
      return
    }
    match cur {
      Int
      | Void
      | Char
      | Float
      | Double
      | If
      | While
      | Do
      | For
      | Return
      | Break
      | Continue
      | Struct
      | Switch
      | Case
      | Default
      | Typedef
      | Enum
      | Unsigned
      | Long
      | Short
      | Signed
      | Const
      | Bool
      | RBrace => return
      _ => ignore(self.advance())
    }
  }
}

///|
fn Parser::is_type_token(self : Parser) -> Bool {
  if self.check(Int) ||
    self.check(Void) ||
    self.check(Char) ||
    self.check(Float) ||
    self.check(Double) ||
    self.check(Struct) ||
    self.check(Enum) ||
    self.check(Unsigned) ||
    self.check(Long) ||
    self.check(Short) ||
    self.check(Signed) ||
    self.check(Const) ||
    self.check(Volatile) ||
    self.check(Bool) ||
    self.check(Union) {
    return true
  }
  // C++ 模式下 class 和 auto 也是类型 token
  if self.is_cpp_mode && (self.check(Class) || self.check(Auto)) {
    return true
  }
  if self.check(Identifier) {
    let name = self.current().text
    if name == "typeof" ||
      name == "__typeof__" ||
      name == "__typeof" ||
      name == "typeof_unqual" ||
      name == "__typeof_unqual__" ||
      name == "__typeof_unqual" {
      return true
    }
    return self.typedef_names.contains(name)
  }
  false
}

///|
fn Parser::is_static_token(self : Parser) -> Bool {
  self.check(Identifier) && self.current().text == "static"
}

// =========================================================================
// Program（顶层分发：M9/G2 前瞻判定函数 + 穷尽分发——原 9 条 else-if +
// 内联 save/advance/restore 前瞻收口于此。判定只读不推进（索引扫描），
// 分发分支保持原消费行为，行为与 Rust lib.rs parse_program 逐字节一致）
// =========================================================================

///|
/// 顶层构造判定结果（穷尽分发面——新增顶层构造漏分支即编译红）。
priv enum TopLevelKind {
  StaticAssertDecl
  AttributePrefix
  TypedefPlain
  TypedefStructDecl
  TypedefEnumDecl
  EnumDecl
  EnumVarOrFunc
  StructVarOrFunc
  StructClassLike
  StructDecl
  UnionDecl
  CppClassDecl
  CppTemplateDecl
  ExternDecl
  StaticVarOrFunc
  TypeVarOrFunc
  UnexpectedTop
}

///|
/// 顶层前瞻判定（M9：集中全部"这是什么顶层构造"的扫描；只读，不动
/// pos——替代原各分支内联的 save/advance/restore 试探，病灶形态
/// （前瞻逻辑分散）就此收口）。优先序与原 else-if 链一致。
fn Parser::classify_top_level(self : Parser) -> TopLevelKind {
  let len = self.tokens.length()
  let ty_at = fn(i : Int) -> @token.TokenType {
    if i < len {
      self.tokens[i].ty
    } else {
      Eof
    }
  }
  if self.check(Identifier) &&
    (
      self.peek(0).text == "_Static_assert" ||
      self.peek(0).text == "static_assert"
    ) {
    return StaticAssertDecl
  }
  // E3：顶层 [[属性]] 前缀
  if self.check(LBracket) && ty_at(self.pos + 1) == LBracket {
    return AttributePrefix
  }
  if self.check(Typedef) {
    // typedef struct [名] { → struct 定义别名；否则掉回普通 typedef
    let mut la = self.pos + 1
    if ty_at(la) == Struct {
      la += 1
      if ty_at(la) == Identifier {
        la += 1
      }
      if ty_at(la) == LBrace {
        return TypedefStructDecl
      }
    }
    // typedef enum [名] [: 底层类型] { → enum 定义别名
    la = self.pos + 1
    if ty_at(la) == Enum {
      la += 1
      if ty_at(la) == Identifier {
        la += 1
      }
      // C23 enum : T：底层类型子句不改变"是否 enum 定义"的判定
      if ty_at(la) == Colon {
        while la < len && ty_at(la) != LBrace && ty_at(la) != Semicolon {
          la += 1
        }
      }
      if ty_at(la) == LBrace {
        return TypedefEnumDecl
      }
    }
    return TypedefPlain
  }
  if self.check(Enum) {
    let mut la = self.pos + 1
    if ty_at(la) == Identifier {
      la += 1
    }
    if ty_at(la) == Colon {
      while la < len && ty_at(la) != LBrace && ty_at(la) != Semicolon {
        la += 1
      }
    }
    if ty_at(la) == LBrace {
      return EnumDecl
    }
    return EnumVarOrFunc
  }
  if self.check(Struct) {
    let mut la = self.pos + 1
    let has_name = ty_at(la) == Identifier
    if has_name {
      la += 1
    }
    if ty_at(la) != LBrace {
      // struct X（无体）——审阅 P2-6 修正：`struct S;` 前向声明归
      // StructDecl（StructVarOrFunc 的 parse_global_var_or_func 对
      // tag+; 形态炸「预期标识符名称」——parse_struct_decl 已有前向
      // 声明跳 body 臂）；`struct S x` 变量声明仍走 VarOrFunc
      if has_name && ty_at(la) == Semicolon {
        return StructDecl
      }
      return StructVarOrFunc
    }
    // 花括号配对扫描（原病灶：手写匹配内联在分发分支；此处只读索引版）
    let mut depth = 0
    while la < len {
      match ty_at(la) {
        LBrace => {
          depth += 1
          la += 1
        }
        RBrace => {
          depth -= 1
          la += 1
          if depth == 0 {
            break
          }
        }
        _ => la += 1
      }
    }
    // 体后 token：Identifier/Star → 变量声明；Semicolon → 纯定义
    let after = ty_at(la)
    let is_var_decl = after == Identifier || after == Star || after == Semicolon
    let is_pure_decl = after == Semicolon
    if is_var_decl && !is_pure_decl {
      return StructVarOrFunc
    }
    if self.is_cpp_mode && has_name {
      return StructClassLike
    }
    return StructDecl
  }
  if self.check(Union) {
    // issue #19 连带（2026-10-06）：union 顶层三形态前瞻——`union U {..}`
    //（tag+body 或匿名 body）= 定义；`union U g;`（tag 后非 LBrace）=
    // 变量声明（旧无条件 UnionDecl 致 parse_struct_body 在声明器处
    // consume LBrace 炸 E2005）
    let p1 = ty_at(self.pos + 1)
    let p2 = ty_at(self.pos + 2)
    if p1 == LBrace || (p1 == Identifier && p2 == LBrace) {
      return UnionDecl
    }
    // 审阅 P2-6（2026-10-07）：`union U;` 前向声明（tag 后直接 ;——
    // Clang 合法；落 StructVarOrFunc 会在 parse_base_type 后把 ; 当
    // 声明器炸 E2005）
    if p1 == Identifier && p2 == Semicolon {
      return UnionDecl
    }
    return StructVarOrFunc
  }
  if self.is_cpp_mode && self.check(Class) {
    return CppClassDecl
  }
  if self.is_cpp_mode && self.check(Template) {
    return CppTemplateDecl
  }
  if self.check(Extern) {
    return ExternDecl
  }
  if self.is_type_token() {
    return TypeVarOrFunc
  }
  if self.is_static_token() {
    return StaticVarOrFunc
  }
  UnexpectedTop
}

///|
/// 顶层穷尽分发（消费行为与原 else-if 链各分支逐字节一致——判定函数
/// 已只读化，各分支从构造头开始解析，不再需要 save/restore 试探）。
fn Parser::dispatch_top_level(
  self : Parser,
  program : @ast.ProgramNode,
  kind : TopLevelKind,
) -> Unit {
  match kind {
    StaticAssertDecl => self.parse_static_assert(0)
    AttributePrefix => self.skip_attributes()
    TypedefStructDecl => self.parse_typedef_struct_decl(program, 0)
    TypedefEnumDecl => self.parse_typedef_enum_decl(program, 0)
    TypedefPlain => self.parse_typedef(0)
    EnumDecl => self.parse_enum_decl(program, 0)
    EnumVarOrFunc => self.parse_global_var_or_func(program, false, false)
    StructVarOrFunc => self.parse_global_var_or_func(program, false, false)
    StructClassLike => self.parse_cpp_class_like_struct_decl(program)
    StructDecl => {
      let struct_decl = self.parse_struct_decl(0)
      if self.is_cpp_mode {
        self.typedef_names.set(
          struct_decl.name,
          @ast.Type::struct_type(struct_decl.name),
        )
      }
      program.structs.push(struct_decl)
      // issue #7 顶层形态：`struct [S] { ... } s;` body 后声明器组；
      // 前向声明（fields 空且 ; 已消费——审阅 P2-6）跳过 trailing
      if struct_decl.fields.length() > 0 {
        self.parse_aggregate_trailing_globals(
          program,
          @ast.Type::struct_type(struct_decl.name),
        )
      }
    }
    UnionDecl => {
      let decl = self.parse_union_decl(0)
      program.unions.push(decl)
      // issue #7 顶层形态（2026-10-06）：`union [U] { ... } g;` body 后
      // 声明器组 → 全局变量（parse_union_decl 已收尾 ; 或停在声明器处）
      // 前向声明（fields 空且 ; 已消费——审阅 P2-6）跳过 trailing
      if decl.fields.length() > 0 {
        self.parse_aggregate_trailing_globals(
          program,
          @ast.Type::union_type(decl.name),
        )
      }
    }
    CppClassDecl => self.parse_cpp_class_decl(program)
    CppTemplateDecl => self.parse_cpp_template_decl(program)
    ExternDecl => {
      ignore(self.advance()) // consume 'extern'
      self.parse_global_var_or_func(program, false, true)
    }
    StaticVarOrFunc => {
      ignore(self.advance()) // consume 'static'
      self.parse_global_var_or_func(program, true, false)
    }
    TypeVarOrFunc => self.parse_global_var_or_func(program, false, false)
    UnexpectedTop => {
      let cur = self.current()
      self.errors.push({
        message: "预期 struct、函数或全局变量声明，找到: \{cur.text}",
        line: cur.loc.line,
        column: cur.loc.column,
        code: @diag.ErrorCode::E2005_ExpectedSemicolon.code(),
      })
      ignore(self.advance())
    }
  }
}

///|
fn Parser::parse_program(self : Parser) -> @ast.ProgramNode? {
  let program = @ast.ProgramNode::empty()
  self.program_sink = Some(program)
  while !self.is_at_end() {
    let round_start = self.pos
    // 跳过函数前缀修饰符 inline（可能出现在 static/extern 之前或之后）
    while self.check(Inline) {
      ignore(self.advance())
    }
    let kind = self.classify_top_level()
    self.dispatch_top_level(program, kind)
    // 活性内部断言（观测面，不改变控制流——照搬的推进逻辑本身三层兜底）
    if self.pos == round_start {
      self.stall_count += 1
      // G1 熔断：主循环零推进仅计数（照搬 Rust），超限强推出下界
      ignore(self.stall_breaker())
    }
  }
  Some(program)
}

///|

///|
/// 从当前位置前瞻，跳过连续的 `*` 指针前缀（C++ 模式含 &/&&），返回跳过
/// 后的 token 索引。
fn Parser::look_ahead_skip_stars(self : Parser) -> Int {
  let mut lookahead = self.pos
  while lookahead < self.tokens.length() {
    match self.tokens[lookahead].ty {
      Star => lookahead += 1
      Ampersand | AndAnd =>
        if self.is_cpp_mode {
          lookahead += 1
        } else {
          break
        }
      _ => break
    }
  }
  lookahead
}

///|
fn Parser::parse_global_var_or_func(
  self : Parser,
  program : @ast.ProgramNode,
  is_static : Bool,
  is_extern : Bool,
) -> Unit {
  let checkpoint = self.save()
  let base_type = self.parse_base_type(0)
  // C++ 构造函数类外定义：Counter::Counter() { ... }
  if self.try_parse_cpp_ctor_out_of_line(
      program, base_type, is_static, is_extern,
    ) {
    return
  }
  // 前瞻：跳过前导 *，检查是否是 identifier (
  let lookahead = self.look_ahead_skip_stars()
  let is_func_decl = if lookahead < self.tokens.length() &&
    self.tokens[lookahead].ty == Identifier {
    if lookahead + 1 < self.tokens.length() &&
      self.tokens[lookahead + 1].ty == LParen {
      true
    } else if self.is_cpp_mode &&
      lookahead + 3 < self.tokens.length() &&
      self.tokens[lookahead + 1].ty == ColonColon &&
      self.tokens[lookahead + 2].ty == Identifier &&
      self.tokens[lookahead + 3].ty == LParen {
      // C++ qualified name: Bar::set(...)
      true
    } else {
      false
    }
  } else {
    false
  }
  if is_func_decl {
    self.restore(checkpoint)
    program.funcs.push(self.parse_func_decl(is_static, is_extern, 0))
  } else if self.try_parse_cpp_qualified_static_field(
      program, base_type, is_static, is_extern,
    ) {
    // 已由 cpp 模块处理
  } else {
    let v = self.parse_var_declarator(base_type, 0)
    let ty = v.0
    let name = v.1
    let init = if is_extern {
      None
    } else if self.match_token(Assign) {
      if self.check(LBrace) {
        Some(self.parse_init_list(0))
      } else {
        Some(self.parse_assign(0))
      }
    } else {
      None
    }
    // loc 取初始化器解析后的 previous（Rust 现状口径：global loc 落在
    // 初始化器末 token——无初始化时落在名字 token）
    let prev = self.previous()
    let loc = @source.SourceLoc::new(prev.loc.line, prev.loc.column)
    program.globals.push({
      ..Default::default(),
      loc,
      ty,
      name,
      init,
      is_static,
      is_extern,
    })
    self.parsed_var_types.push((name, ty))
    while self.match_token(Comma) {
      let ex = self.parse_var_declarator(base_type, 0)
      let extra_ty = ex.0
      let extra_name = ex.1
      let extra_init = if is_extern {
        None
      } else if self.match_token(Assign) {
        if self.check(LBrace) {
          Some(self.parse_init_list(0))
        } else {
          Some(self.parse_assign(0))
        }
      } else {
        None
      }
      let prev2 = self.previous()
      let loc2 = @source.SourceLoc::new(prev2.loc.line, prev2.loc.column)
      program.globals.push({
        ..Default::default(),
        loc: loc2,
        ty: extra_ty,
        name: extra_name,
        init: extra_init,
        is_static,
        is_extern,
      })
      self.parsed_var_types.push((extra_name, extra_ty))
    }
    // issue #48（Clang ParseDecl 同款 balanced-brace recovery）：顶层声明
    // 器组后缺 ';' 且 '{' 紧随 = 漏写参数括号试图写函数体的强信号——病根
    // 报错后整体吞配平块 + 尾 ';'，顶层循环从下一声明恢复。旧路径
    //（synchronize 停到类型关键字/'}'）会令函数体行逐 token 暴露在顶层，
    // 级联数 ∝ 首错后 token 数（`int main{` 学生实测 8 条 E2005 vs Clang
    // 1 error）。无 '{' 紧随的缺 ';' 形状维持旧恢复不动（形状锁定锚）。
    if self.check(Semicolon) {
      ignore(self.advance())
    } else {
      let prev = self.previous()
      self.errors.push({
        message: "全局变量声明后预期 ';'",
        line: prev.loc.line,
        column: prev.loc.column,
        code: @diag.ErrorCode::E2005_ExpectedSemicolon.code(),
      })
      if self.check(LBrace) {
        self.skip_balanced_braces()
        if self.check(Semicolon) {
          ignore(self.advance())
        }
      } else {
        self.synchronize([Semicolon])
      }
    }
  }
}

///|
/// 吞一个 `{ ... }` 配平块（嵌套计数；未闭合吞到 EOF——垃圾变体
/// 「首错行内丢弃」语义锚：块内任意内容恒零额外诊断）。仅在入口
/// 确认是 LBrace 后调用；返回时 pos 在块闭合 '}' 之后（或 EOF）。
fn Parser::skip_balanced_braces(self : Parser) -> Unit {
  if !self.check(LBrace) {
    return
  }
  ignore(self.advance())
  let mut depth = 1
  while !self.is_at_end() && depth > 0 {
    match self.current().ty {
      LBrace => {
        depth += 1
        ignore(self.advance())
      }
      RBrace => {
        depth -= 1
        ignore(self.advance())
      }
      _ => ignore(self.advance())
    }
  }
}

///|
/// 在模板实参列表中解析非类型表达式实参（照搬 X1 的显式视图等价形态：
/// Rust `mem::take` + 切片替换 → 本实现保存 (start, end) 边界、用索引
/// 偏移直接在原数组上解析——语义保持 `pos = saved_pos + consumed`）。
fn Parser::parse_template_arg_expr(self : Parser, depth : Int) -> @ast.Expr {
  let found = self.find_template_arg_delimiter()
  let end_idx = found.0
  if end_idx <= self.pos {
    let cur = self.current()
    self.errors.push({
      message: "空模板非类型实参",
      line: cur.loc.line,
      column: cur.loc.column,
      code: @diag.ErrorCode::E2003_ExpectedExpr.code(),
    })
    return @ast.Expr::Literal(
      0,
      @source.SourceLoc::new(cur.loc.line, cur.loc.column),
      @ast.Type::int(),
    )
  }
  // 显式子视图（X8）：临时把 pos 域限制到 [saved_pos, end_idx)，解析后
  // 回填——tokens 数组本身不动，等价 Rust 的子流替换
  let saved_pos = self.pos
  let view : Array[@token.Token] = []
  for i in saved_pos..<end_idx {
    view.push(self.tokens[i])
  }
  let sub = Parser::with_mode(view, self.is_cpp_mode)
  // 符号表与父共享引用（Rust 共享 self 的同款副作用：子流写入直接落父
  // 状态）；错误表为子流独立数组，解析完按序推回。已知等价边界：子流
  // 内深度超限只跳到 view 尾（Rust 跳到父流尾）——256 层模板实参嵌套
  // 属语料外病态，登记执行记录
  sub.typedef_names = self.typedef_names
  sub.template_names = self.template_names
  let expr = sub.parse_assign(depth)
  self.pos = saved_pos + sub.pos
  for e in sub.errors {
    self.errors.push(e)
  }
  self.next_lambda_id = sub.next_lambda_id
  expr
}

///|
/// 从当前位置扫描模板实参结束位置（顶层逗号或匹配的 `>`；跳过 ()[]{}
/// 与嵌套 <>）。返回索引指向分隔符，调用者负责消费。
fn Parser::find_template_arg_delimiter(
  self : Parser,
) -> (Int, @token.TokenType) {
  let mut i = self.pos
  let mut template_depth = 1
  let mut paren = 0
  let mut bracket = 0
  let mut brace = 0
  while i < self.tokens.length() {
    let t = self.tokens[i].ty
    match t {
      LParen => paren += 1
      RParen => if paren > 0 { paren -= 1 }
      LBracket => bracket += 1
      RBracket => if bracket > 0 { bracket -= 1 }
      LBrace => brace += 1
      RBrace => if brace > 0 { brace -= 1 }
      Lt => if paren == 0 && bracket == 0 && brace == 0 { template_depth += 1 }
      Gt =>
        if paren == 0 && bracket == 0 && brace == 0 {
          template_depth -= 1
          if template_depth == 0 {
            return (i, Gt)
          }
        }
      Comma =>
        if template_depth == 1 && paren == 0 && bracket == 0 && brace == 0 {
          return (i, Comma)
        }
      _ => ()
    }
    i += 1
  }
  (i, Eof)
}

///|
/// 顶层聚合声明 body 后的可选声明器组（issue #7：`union {...} g, h;`）——
/// parse_struct_decl/parse_union_decl 的尾部在声明器处停（不报错）时，
/// 由本函数把声明器组收为全局变量并消费收尾 ';'。已收尾（当前为下一
/// 声明起点）则空操作。
fn Parser::parse_aggregate_trailing_globals(
  self : Parser,
  program : @ast.ProgramNode,
  base : @ast.Type,
) -> Unit {
  if self.check(Semicolon) {
    ignore(self.advance())
    return
  }
  if self.is_at_end() || self.check(RBrace) {
    return
  }
  // 声明器组（Identifier/* 起头）。存储类/限定符中只有 static 是
  // Identifier 文本词（keyword 表无 static——is_static_token 同款文本
  // 特判；auto/register/extern/inline/const/volatile/typedef 均为关键字
  // token，进不了本分支——审阅 P3-4 旧死分支与 E5 注释纠正）
  if !(self.check(Identifier) || self.current().ty == Star) {
    return
  }
  if self.check(Identifier) {
    let t = self.current().text
    // static 是 Identifier 文本词（keyword 表无）；_Static_assert/
    // static_assert 由顶层 StaticAssertDecl 分支处理（trailing 若吞会
    // 把断言解析成函数声明器——issue #13 顶层组合形态实测）
    if t == "static" || t == "_Static_assert" || t == "static_assert" {
      return
    }
  }
  while true {
    let d = self.parse_declarator(base, 0)
    let prev = self.previous()
    let loc = @source.SourceLoc::new(prev.loc.line, prev.loc.column)
    program.globals.push({
      ..Default::default(),
      loc,
      ty: d.0,
      name: d.1,
      init: None,
    })
    self.parsed_var_types.push((d.1, d.0))
    if !self.match_token(Comma) {
      break
    }
  }
  ignore(self.consume(Semicolon, "声明后预期 ';'"))
}

///|
/// 已解析聚合表快照（static_assert 求值消费——issue #13）。
fn Parser::snapshot_structs_table(
  self : Parser,
) -> Map[String, Array[@ast.StructField]] {
  let m : Map[String, Array[@ast.StructField]] = Map([])
  for t in self.parsed_aggregates {
    let (name, is_union, fields) = t
    if !is_union {
      m.set(name, fields)
    }
  }
  m
}

///|
fn Parser::snapshot_unions_table(
  self : Parser,
) -> Map[String, Array[@ast.StructField]] {
  let m : Map[String, Array[@ast.StructField]] = Map([])
  for t in self.parsed_aggregates {
    let (name, is_union, fields) = t
    if is_union {
      m.set(name, fields)
    }
  }
  m
}

///|
/// 变量类型快照（后声明覆盖语义——倒序首个命中）
fn Parser::snapshot_var_types(self : Parser) -> Map[String, @ast.Type] {
  let m : Map[String, @ast.Type] = Map([])
  for t in self.parsed_var_types {
    let (n, ty) = t
    m.set(n, ty)
  }
  m
}
