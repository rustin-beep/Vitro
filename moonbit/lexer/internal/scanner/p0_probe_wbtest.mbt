///|
/// P0 静默错值锚（2026-09-21 审阅）：2^64 = 18446744073709551616 的尾位 6
/// 命中 parse_u64 十进制加法溢出缺口（radix ∤ 2^64 时 UMAX 邻域），
/// 此前环绕成 0 放行 Some(0)——globals 静默产 0 而 Rust 侧 E1006 拒绝。
/// 修复：加法后单调性回绕检测。本锚先红（errors=0）后绿留痕。
test "p0 ull 2^64 decimal overflow reports E1006" {
  let errs : Array[@token.LexError] = []
  let toks = scan_fragment(
    "unsigned long long g = 18446744073709551616ull;",
    base_byte_off=0,
    base_line=1,
    base_column=1,
    file_id=0,
    errors=errs,
  )
  assert_eq(errs.length(), 1)
  assert_true(
    errs[0].message.has_prefix(
      "整数常量 18446744073709551616 超出可表示范围",
    ),
  )
  assert_true(errs[0].code is E1006_UnsupportedFeature)
  // 溢出 token 兜底值 0（继续收后续诊断——Rust 同款）
  assert_eq(toks.length(), 7)
}

///|
/// 缺口邻域全扫锚：UMAX 邻域十进制的加法溢出面（...611..615 合法 +
/// 616..619 拒绝）——2^64 只是其中一个值，缺口是区间不是单点。
test "p0 UMAX neighborhood decimal boundary" {
  // UMAX = 18446744073709551615 合法
  for tail in ["18446744073709551615", "18446744073709551611"] {
    let errs : Array[@token.LexError] = []
    ignore(
      scan_fragment(
        "unsigned long long g = \{tail}ull;",
        base_byte_off=0,
        base_line=1,
        base_column=1,
        file_id=0,
        errors=errs,
      ),
    )
    assert_eq(errs.length(), 0)
  }
  // UMAX+1 ..= UMAX+4 拒绝（2^64=…616 至 …619）
  for
    tail in [
      "18446744073709551616", "18446744073709551617", "18446744073709551618", "18446744073709551619",
    ] {
    let errs : Array[@token.LexError] = []
    ignore(
      scan_fragment(
        "unsigned long long g = \{tail}ull;",
        base_byte_off=0,
        base_line=1,
        base_column=1,
        file_id=0,
        errors=errs,
      ),
    )
    assert_eq(errs.length(), 1)
  }
}
