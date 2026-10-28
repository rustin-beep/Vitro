// #223 红→绿锚（2026-10-25）：「函数已声明但未定义」诊断此前走 codegen
// 无码过渡——serve 层把 gen_errors 包装成 code=0（E0/Unknown 兜底，#70
// 第一步注释自证「立码段拍板后换真码」），下游按码查卡落空，且 E0 通用卡
// 文案「内部错误（未分类）」对这条合法用户错误教学面失准。本批立码
// E3089（E3xxx 语义段顺延：3001–3088 连续占满）+ catalog 卡 +
// fix_payloads 静态载荷。锚四件：error_code=3089 / severity error /
// 文案语义不变（只换码不换话）/ fix_suggestion 非空。

///|
test "issue223_declared_not_defined_gets_e3089" {
  let s = @session.Session::new()
  let (resp, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int f(int x);\\nint main() { return f(1); }\\n\"}}",
  )
  assert_true(
    resp.contains("\"ok\":false"),
    msg="一体化如实报：编译失败",
  )
  let diags = s.compile.diagnostics
  assert_eq(diags.length(), 1, msg="单条诊断")
  assert_eq(diags[0].error_code, 3089, msg="立码 E3089（旧值 E0 兜底）")
  assert_eq(diags[0].severity, 0, msg="severity error")
  assert_eq(
    diags[0].line,
    2,
    msg="行号直存（旧手扫形态锚承接：调用点第 2 行）",
  )
  assert_eq(
    diags[0].column,
    21,
    msg="列锚真值（旧口径恒 1；f(1) 字节列）",
  )
  assert_true(
    diags[0].message.contains("已声明但未定义"),
    msg="文案语义保持（#205 修复批文案零改动）",
  )
  assert_true(
    diags[0].fix_suggestion.length() > 0,
    msg="fix_suggestion 非空（静态载荷）",
  )
}
