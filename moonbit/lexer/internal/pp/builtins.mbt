///|
/// 内置宏表（照搬 `macros.rs` + `macro_table.rs::builtin` 全量语义）。
/// 纯数据表驱动（勘察 ⑤-8：521 行手写 token 构造改表驱动）——对象宏以
/// `(名, TokenType, text)` 三元组登记；`va_*` 四条函数式宏（va_start/va_arg/
/// va_end/va_copy）为显式 token 列表
///（body token 的 `(ty, text)` 逐项照搬，宏体不经 number() 重扫——负号数字
/// 如 INT_MIN 的 "-2147483648" 是**单个 Number token**，text 带负号，parser
/// 直接按文本取值，`macros.rs:195` 口径注释）。
fn builtin_macro_table() -> Map[String, @token.MacroDef] {
  let m : Map[String, @token.MacroDef] = Map([])
  // (name, ty, text) —— stdio/stdlib/limits/stdbool 常量宏
  let object_macros : Array[(String, @token.TokenType, String)] = [
    ("EOF", Number, "-1"),
    ("EXIT_SUCCESS", Number, "0"),
    ("EXIT_FAILURE", Number, "1"),
    ("RAND_MAX", Number, "32767"),
    ("SEEK_SET", Number, "0"),
    ("SEEK_CUR", Number, "1"),
    ("SEEK_END", Number, "2"),
    ("INT_MAX", Number, "2147483647"),
    ("INT_MIN", Number, "-2147483648"),
    ("LONG_MAX", Number, "2147483647"),
    ("LONG_MIN", Number, "-2147483648"),
    ("CHAR_BIT", Number, "8"),
    ("SCHAR_MIN", Number, "-128"),
    ("SCHAR_MAX", Number, "127"),
    ("UCHAR_MAX", Number, "255"),
    ("SHRT_MIN", Number, "-32768"),
    ("SHRT_MAX", Number, "32767"),
    ("USHRT_MAX", Number, "65535"),
    ("UINT_MAX", UnsignedLiteral, "4294967295"),
    ("ULONG_MAX", UnsignedLiteral, "4294967295"),
    ("LLONG_MAX", LongLiteral, "9223372036854775807"),
    ("LLONG_MIN", LongLiteral, "-9223372036854775808"),
    ("ULLONG_MAX", UnsignedLiteral, "18446744073709551615"),
    ("true", Number, "1"),
    ("false", Number, "0"),
  ]
  for pair in object_macros {
    let (name, ty, text) = pair
    m[name] = @token.MacroDef::Object(body=[synth_token(ty, text)])
  }
  // 病 15 残余收尾（#61，2026-10-10）：stdin/stdout/stderr 从 Number 单
  // token 改为显式 cast 宏体 ((FILE *)n)——FILE* 赋值/传参/比较全语境一次
  // 干净（旧 Number 形态下 `FILE *f = stdout` 走通用 int→指针赋值吃
  // E3054，`typedef void* FILE` 使 typeck 无法从类型识别 std 流宏）；
  // host 层按值分流不变（cast 不改值）。两项登记性影响：① `#if stdout`
  // 语境改后非法（cast 体进 #if 算术域）——真 C 对 FILE* 宏同判不支持
  //（UCRT 的 __acrt_iob_func(1) 在 #if 里同样过不了），改后更贴真 C；
  // ② 未 include stdio.h 而用 stdout：两形态**等价照跑**（旧 ⇒1 直跑；
  // 新展开 ((FILE*)1) 中 FILE 走 typeck 未知类型 cast 的既有宽容面——
  // 真 C 报三错，该差距属未知类型面非本批）。
  for triple in [("stdin", "0"), ("stdout", "1"), ("stderr", "2")] {
    let (name, val) = triple
    m[name] = @token.MacroDef::Object(body=[
      synth_token(LParen, "("),
      synth_token(LParen, "("),
      synth_token(Identifier, "FILE"),
      synth_token(Star, "*"),
      synth_token(RParen, ")"),
      synth_token(Number, val),
      synth_token(RParen, ")"),
    ])
  }
  // E2 预定义宏族：__STDC_VERSION__ 报 202311L 名义锚点（把版本当能力探测的
  // 病根由三层配套解决，见 Rust macro_table.rs 注释）；__VITRO_SUBSET__ 引擎探测
  m["__STDC_VERSION__"] = @token.MacroDef::Object(body=[
    synth_token(Number, "202311L"),
  ])
  m["__VITRO_SUBSET__"] = @token.MacroDef::Object(body=[
    synth_token(Number, "1"),
  ])
  // stdarg.h：标准写法 → 内部 host func 调用（token 序列照 macros.rs 逐项搬）
  m["va_start"] = @token.MacroDef::Function(
    params=["ap", "last"],
    body=[
      synth_token(Identifier, "__vitro_va_start"),
      synth_token(LParen, "("),
      synth_token(Ampersand, "&"),
      synth_token(LParen, "("),
      synth_token(Identifier, "ap"),
      synth_token(RParen, ")"),
      synth_token(Comma, ","),
      synth_token(Ampersand, "&"),
      synth_token(LParen, "("),
      synth_token(Identifier, "last"),
      synth_token(RParen, ")"),
      synth_token(Comma, ","),
      synth_token(Sizeof, "sizeof"),
      synth_token(LParen, "("),
      synth_token(Identifier, "last"),
      synth_token(RParen, ")"),
      synth_token(RParen, ")"),
    ],
    variadic=false,
  )
  m["va_arg"] = @token.MacroDef::Function(
    params=["ap", "type"],
    body=[
      synth_token(Star, "*"),
      synth_token(LParen, "("),
      synth_token(Identifier, "type"),
      synth_token(Star, "*"),
      synth_token(RParen, ")"),
      synth_token(Identifier, "__vitro_va_arg"),
      synth_token(LParen, "("),
      synth_token(Ampersand, "&"),
      synth_token(LParen, "("),
      synth_token(Identifier, "ap"),
      synth_token(RParen, ")"),
      synth_token(Comma, ","),
      synth_token(Sizeof, "sizeof"),
      synth_token(LParen, "("),
      synth_token(Identifier, "type"),
      synth_token(RParen, ")"),
      synth_token(RParen, ")"),
    ],
    variadic=false,
  )
  m["va_end"] = @token.MacroDef::Function(
    params=["ap"],
    body=[
      synth_token(Identifier, "__vitro_va_end"),
      synth_token(LParen, "("),
      synth_token(Ampersand, "&"),
      synth_token(LParen, "("),
      synth_token(Identifier, "ap"),
      synth_token(RParen, ")"),
      synth_token(RParen, ")"),
    ],
    variadic=false,
  )
  m
}

///|
/// 合成 token（内置宏体专用——line/column/file_id 全 0，Rust 同构）。
fn synth_token(ty : @token.TokenType, text : String) -> @token.Token {
  {
    ty,
    text,
    loc: { line: 0, column: 0, file_id: 0, },
    byte_off: 0,
    real_line: 0,
  }
}

///|
/// 宏体逐 token 相等比较（文本与类型都一致才算"相同定义"——W1018 判据）。
fn bodies_identical(a : Array[@token.Token], b : Array[@token.Token]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    if a[i].ty != b[i].ty || a[i].text != b[i].text {
      return false
    }
  }
  true
}

///|
/// 宏参数表相等（区分对象式/函数式——同型才比参数）。
fn macro_defs_equivalent(a : @token.MacroDef, b : @token.MacroDef) -> Bool {
  // W1018 判据复刻 Rust 无分型口径（S2 审阅 P2）：Object vs Function(params=[])
  // 在 Rust 视角 params 同为空——body 相同即"相同定义"静默放行（此前跨型
  // 直接判不等价，`FOO 1` 后 `FOO() 1` 误报遮蔽）
  let params_of = (d : @token.MacroDef) => {
    match d {
      Object(..) => []
      Function(params~, ..) => params
    }
  }
  match (a, b) {
    (Object(body~), Object(body=body2)) => bodies_identical(body, body2)
    (Function(params~, body~), Function(params=p2, body=body2)) =>
      params == p2 && bodies_identical(body, body2)
    (Object(body~), Function(body=body2, ..))
    | (Function(body~, ..), Object(body=body2)) =>
      params_of(a).length() == 0 &&
      params_of(b).length() == 0 &&
      bodies_identical(body, body2)
  }
}

///|
/// `#define`（W1018 遮蔽警告文案逐字照搬；**无 4096 静默上限**——勘察 ③-9
/// 修复：Rust 超限静默丢弃 `#define`，零诊断指向真因）。
fn[P] Pp::define_macro(
  self : Pp[P],
  name : String,
  def : @token.MacroDef,
  line : Int32,
) -> Unit {
  match self.macros.get(name) {
    Some(existing) =>
      // issue #14 销案（2026-10-06）：stdarg 四宏（va_start/va_arg/
      // va_end/va_copy）的引擎双源（内置宏表 token 序列 ↔ stdarg.h
      // 存根文本重扫）语义同构、token 序列有实现级漂移——C 实现的
      // va 族双形态对用户透明（Clang 零警告）；该四名的重定义不报
      // W1018（后定义者照常覆盖，行为不变）
      if !macro_defs_equivalent(existing, def) &&
        name != "va_start" &&
        name != "va_arg" &&
        name != "va_end" &&
        name != "va_copy" {
        self.warnings.push({
          message: "宏 '\{name}' 被重复定义且宏体不同（遮蔽了先前的定义）。若非有意为之，请先 #undef 或改名",
          loc: { line, column: 0, file_id: self.current_file_id(), },
          code: W1018_MacroShadowing,
        })
      }
    None => ()
  }
  self.macros[name] = def
}

///|
/// #221（2026-10-22，C99 §6.10.8 预定义宏）：`__FILE__`/`__LINE__` 的
/// 值依赖**使用点位置**——静态宏表不可表达，展开循环（expander.mbt 的
/// macros 查表前）按 token 特判合成。此处集中放合成件：
/// display_name_of 取路径 basename（断言/日志输出惯例），loc 合成到
/// 使用点（诊断归位）。
fn display_name_of(path : String) -> String {
  let mut name = path
  for sep in ["/", "\\"] {
    match name.split(sep).last() {
      Some(tail) if tail.length() > 0 => name = tail.to_string()
      _ => ()
    }
  }
  name
}

///|
/// `__FILE__` 展开 token：StringLiteral（值 = 使用点所属文件的 basename）。
fn synth_file_macro(use_site : @token.Token, fname : String) -> @token.Token {
  {
    ty: @token.TokenType::String,
    text: fname,
    loc: use_site.loc,
    byte_off: use_site.byte_off,
    real_line: use_site.real_line,
  }
}

///|
/// `__LINE__` 展开 token：Number（值 = 使用点**真实行号** real_line——
/// 仿古坐标下 include 段的 loc.line 是拼接补偿值（负数/偏移），C 语义
/// 的 __LINE__ 是原文件物理行，两者在主文件重合、include 段分叉）。
fn synth_line_macro(use_site : @token.Token) -> @token.Token {
  synth_line_macro_at(use_site, use_site.real_line)
}

///|
/// `__LINE__` 合成（行号由调用方分派——顶层直用 real_line / 拼接段
/// 还原 / 宏体调用点取展开点行）。
fn synth_line_macro_at(use_site : @token.Token, line : Int32) -> @token.Token {
  {
    ty: @token.TokenType::Number,
    text: "\{line}",
    loc: use_site.loc,
    byte_off: use_site.byte_off,
    real_line: use_site.real_line,
  }
}

///|
/// #221：预定义宏的**调用点替换**——`__FILE__`/`__LINE__` 出现在宏体
/// （`#define ASSERT(x) fail(__FILE__, __LINE__)`）时，C 语义取**展开
/// 点**的文件与行（C99 §6.10.8.1），而非宏定义处。展开循环的内层特判
/// 看到的是 body token（loc=定义处），故在 Object/Function 展开入口先
/// 把 body 内的预定义宏 token 按调用点就地替换（内层递归不再遇到）。
fn substitute_predefined(
  body : Array[@token.Token],
  call_site : @token.Token,
  file_name : String,
  line : Int32,
) -> Array[@token.Token] {
  let out : Array[@token.Token] = []
  for bt in body {
    if bt.text == "__FILE__" && bt.ty is Identifier {
      out.push(synth_file_macro(call_site, file_name))
    } else if bt.text == "__LINE__" && bt.ty is Identifier {
      out.push(synth_line_macro_at(call_site, line))
    } else {
      out.push(bt)
    }
  }
  out
}
