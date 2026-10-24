///|
test "scan_raw basic tokens" {
  let r = scan_raw(
    @utf8.encode(
      "int x = 42; // note\n/* blk */ if (x >= 'a') printf(\"hi\\n\");",
    ),
  )
  let summary = r.tokens
    .map(t => {
      "\{t.ty.to_name()}:\{t.text}@\{t.loc.line}:\{t.loc.column}+\{t.byte_off}"
    })
    .join(" | ")
  inspect(
    summary,
    content=(
      #|Int:int@1:1+0 | Identifier:x@1:5+4 | Assign:=@1:7+6 | Number:42@1:9+8 | Semicolon:;@1:11+10 | If:if@2:11+30 | LParen:(@2:14+33 | Identifier:x@2:15+34 | Ge:>=@2:17+36 | CharLiteral:97@2:20+39 | RParen:)@2:23+42 | Identifier:printf@2:25+44 | LParen:(@2:31+50 | String:hi
      #|@2:32+51 | RParen:)@2:38+57 | Semicolon:;@2:39+58 | Eof:@2:40+59
    ),
  )
  assert_eq(r.errors.length(), 0)
}

///|
test "scan_raw hex float suffix dispatch" {
  let r = scan_raw(
    @utf8.encode("0xFF 3.14f .5 1e5 0b1010 1'000 42ULL 8000000000LL"),
  )
  let summary = r.tokens.map(t => "\{t.ty.to_name()}:\{t.text}").join(" ")
  inspect(
    summary,
    content=(
      #|Number:255 FloatLiteral:3.14f FloatLiteral:.5 FloatLiteral:1e5 Number:10 Number:1000 UnsignedLiteral:42ull LongLiteral:8000000000 Eof:
    ),
  )
  assert_eq(r.errors.length(), 0)
}

///|
test "scan_raw unknown char collects error" {
  let r = scan_raw(@utf8.encode("int $x;"))
  assert_eq(r.errors.length(), 1)
  inspect(@diag.ErrorCode::code(r.errors[0].code), content="1001")
  inspect(r.tokens[1].ty.to_name(), content="Unknown")
}

///|
test "scan_raw cpp mode and hash" {
  let r = scan_raw(@utf8.encode("a ## b # c"), cpp_mode=false)
  let summary = r.tokens.map(t => t.ty.to_name()).join(" ")
  inspect(summary, content="Identifier HashHash Identifier Hash Identifier Eof")
}

///|
test "scan_raw c11 whitespace vtab formfeed" {
  // C11 §6.4p3 white-space 全集：space / \t / \n / \v(0x0B) / \f(0x0C) / \r。
  // \v 曾缺（Rust is_ascii_whitespace 集合不含 \x0B 的照搬期分歧——issue #55）
  let r = scan_raw(@utf8.encode("int\u{B} x\u{C} =\u{B}1;\r\n"))
  let summary = r.tokens.map(t => "\{t.ty.to_name()}:\{t.text}").join(" ")
  inspect(
    summary,
    content="Int:int Identifier:x Assign:= Number:1 Semicolon:; Eof:",
  )
  assert_eq(r.errors.length(), 0)
}

///|
/// #247（2026-10-22，C99 §6.4.4.4 小数部分缺省）：`10.` / `10.e5` 是
/// 完整浮点常量——旧扫描把尾点拆出去按成员访问处理（E2005/E3041 误拒）。
/// 点后三态锚：数字（既有）、e 指数（10.e5）、常量终结符（10.;）。
test "scan_raw trailing dot float literal" {
  let r = scan_raw(@utf8.encode("double a = 10.; double b = 10.e5;"))
  let summary = r.tokens.map(t => "\{t.ty.to_name()}:\{t.text}").join(" ")
  inspect(
    summary,
    content="Double:double Identifier:a Assign:= FloatLiteral:10. Semicolon:; Double:double Identifier:b Assign:= FloatLiteral:10.e5 Semicolon:; Eof:",
  )
  assert_eq(r.errors.length(), 0)
}

///|
/// #247 边界：点后标识符起始（`10.x` 非法后缀）维持拆分——教学域显式
/// 拒绝优于静默吞；前导点 `.5` 与 `2.f` 既有形态回归。
test "scan_raw trailing dot boundaries" {
  let r = scan_raw(@utf8.encode(".5 2.f 10.x"))
  let summary = r.tokens.map(t => "\{t.ty.to_name()}:\{t.text}").join(" ")
  inspect(
    summary,
    content="FloatLiteral:.5 FloatLiteral:2.f Number:10 Dot:. Identifier:x Eof:",
  )
  assert_eq(r.errors.length(), 0)
}

///|
/// issue #251 同族格（2026-10-24）：U/UL 后缀超 u32 档的符号域。C11 6.4.4.1
/// U 后缀候选序**全无符号**（unsigned int → unsigned long → unsigned long
/// long；LLP64 前两者 4B）——值 >4B 定型 ULL，clang 零警告；旧发
/// LongLiteral（有符号 8B）符号域错置（`5000000000U < 0` 按无符号应为假、
/// 除法/比较按符号域分流错）。token 裸 text 交 parser UnsignedLiteral 臂按
/// 值域派生（≤UINT_MAX 定 uint、超档定 ULL）。注：十进制**无后缀**大常量
/// 的 E1006 维持（DIFF-LEX-DECL-BIGCONST-01 2026-10-04 台账裁定，翻案
/// 挂 issue #251 待拍板——与本格「U 后缀候选全无符号」的标准地位不同）。
test "issue_251_u_suffix_above_u32_unsigned_domain" {
  let r = scan_raw(@utf8.encode("5000000000U 0x1FFFFFFFFu 4294967295U"))
  let summary = r.tokens.map(t => "\{t.ty.to_name()}:\{t.text}").join(" ")
  inspect(
    summary,
    content="UnsignedLiteral:5000000000 UnsignedLiteral:8589934591 UnsignedLiteral:4294967295 Eof:",
  )
  assert_eq(r.errors.length(), 0)
}

///|
/// #297 token 起始快照锚：text 为规范化值的数字 token（`0x1F`→"31" /
/// `0b101`→"5" / `1'000`→"1000" / `5000000000U` 后缀剥 / `07` 八进制前缀剥）
/// 列 = 源拼写起始列——旧「扫描后列 − 规范化 text 字节数」回推必偏
///（`0x1F` +2、`0b101` +4、`1'000` +1、后缀/前缀剥 +1；E3074 实测
/// vitro 5:16 vs clang 5:14 留证 issue 表）。
test "issue_297_token_start_col_normalized_text" {
  let r = scan_raw(@utf8.encode("  0x1F 0b101 1'000 5000000000U 07"))
  let cols = r.tokens
    .map(t => "\{t.ty.to_name()}:\{t.text}@\{t.loc.column}")
    .join(" ")
  inspect(
    cols,
    content=(
      #|Number:31@3 Number:5@8 Number:1000@14 UnsignedLiteral:5000000000@20 Number:7@32 Eof:@34
    ),
  )
  assert_eq(r.errors.length(), 0)
}

///|
/// #297 跨行 token 起始快照锚：行拼接字符串 token 的 loc = 起始行列
///（旧回推跨过换行 column 重置点——issue 实测报 line 3, column -3，
/// 正确值 line 2 起始列）。
test "issue_297_multiline_token_start_loc" {
  let r = scan_raw(@utf8.encode("char *s = \"ab\\\ncd\"; x"))
  // 字符串 token 起于 1:11（"ab\<LF>cd"），跨行后结束于行 2；分号与 x 在行 2
  let s2 = r.tokens[4]
  assert_true(s2.ty is String, msg="第 7 个 token 应为字符串")
  assert_eq(s2.loc.line, 1, msg="跨行字符串 loc 取起始行")
  assert_eq(s2.loc.column, 11, msg="跨行字符串 loc 取起始列")
  let semi = r.tokens[5]
  assert_true(semi.ty is Semicolon, msg="分号跟随")
  assert_eq(
    semi.loc.line,
    2,
    msg="行 2 的 token 行号不受前 token 跨行影响",
  )
  assert_eq(semi.loc.column, 4, msg="行 2 分号列（cd\" 后）")
}
