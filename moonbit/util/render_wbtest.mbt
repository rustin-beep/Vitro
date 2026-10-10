///|
/// render_template 锚（#60 批二，2026-10-10）：替换单/多参、缺参保留原文
/// （可见失败信号——教学引擎口径，不 abort 不静默）、无占位符透传、
/// 空 name/未闭合原样输出、多传忽略。
test "render_template_basics" {
  assert_eq(
    render_template("第 {line} 行被释放", [("line", "4")]),
    "第 4 行被释放",
  )
  assert_eq(render_template("{a}-{b}-{a}", [("a", "1"), ("b", "2")]), "1-2-1")
  // 缺参：占位符原文保留（可见失败）
  assert_eq(render_template("x {miss} y", [("a", "1")]), "x {miss} y")
  // 无占位符透传；多传忽略
  assert_eq(render_template("plain", [("a", "1")]), "plain")
  assert_eq(render_template("{a}", [("a", "1"), ("b", "2")]), "1")
  // 空 name / 未闭合：原样输出 '{'
  assert_eq(render_template("a {} b", []), "a {} b")
  assert_eq(render_template("a {unclosed", []), "a {unclosed")
}
