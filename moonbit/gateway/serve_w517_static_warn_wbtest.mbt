// #517 P3-13/P3-14（2026-11-14）静态警告面黑盒锚——诊断码 W3098（局部
// 常量除零）/ W3099（未初始化读取）经 compile 全链出口；红→绿锚（stash
// typeck/diag 改动时本组必红）。C 源刻意零字符串字面量（避开三层转义）。

///|
/// P3-13 正面：局部 `int x = 1 / 0;` 须 W3098（全局形态 E3075 在案——
/// serve_compile 既有锚；修前局部零警告，C2 实录）。
test "serve_compile_w517_local_const_divzero_warns_w3098" {
  let s = @session.Session::new()
  let (resp, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main() { int x = 1 / 0; return x; }\\n\"}}",
  )
  assert_true(resp.contains("W3098"), msg="局部常量除零须 W3098 警告")
  assert_true(resp.contains("除以零"), msg="文案须点名除以零形态")
  // W 级不挡编译
  assert_true(resp.contains("\"ok\":true"), msg="W3098 是警告非错误")
}

///|
/// P3-13 增益锚：局部常量溢出（探测路径的 const_eval 副作用）报 W3090
///（修前局部形态零警告——clang -Winteger-overflow 对局部同款）。
test "serve_compile_w517_local_const_overflow_warns_w3090" {
  let s = @session.Session::new()
  let (resp, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main() { int y = 2147483647 + 1; return y; }\\n\"}}",
  )
  assert_true(resp.contains("W3090"), msg="局部常量溢出须 W3090 警告")
  assert_true(resp.contains("\"ok\":true"), msg="W 级不挡编译")
}

///|
/// P3-13 防误报：初始化器含函数调用（非常量树）零新警告（f 给定义，
/// 避开 E3089 已声明未定义的既有防线面）。
test "serve_compile_w517_non_const_init_no_warn" {
  let s = @session.Session::new()
  let (resp, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int f(void) { return 1; }\\nint main() { int z = f(); return z; }\\n\"}}",
  )
  assert_true(
    resp.contains("\"diagnostics\":[]"),
    msg="非常量初始化器零新警告（实际：\{resp}）",
  )
}

///|
/// P3-14 正面：C7 形态 `int u; int v = u + 1;`（读侧在初始化器）+
/// `int w; return w;`（读侧在 return）须 W3099（修前零警告；Vitro
/// 确定性零初始化让学生看不到「忘初始化」）。
test "serve_compile_w517_uninit_read_warns_w3099" {
  let s = @session.Session::new()
  let (resp, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main(void) {\\n    int u;\\n    int v = u + 1;\\n    int w;\\n    return v + w;\\n}\\n\"}}",
  )
  assert_true(resp.contains("W3099"), msg="未初始化读取须 W3099 警告")
  assert_true(
    resp.contains("未初始化的局部变量 'u'"),
    msg="文案须点名变量 u",
  )
  assert_true(resp.contains("\"ok\":true"), msg="W 级不挡编译")
}

///|
/// P3-14 防误报四连：先赋值再用 / 取址传参写入（自定义函数）/ if-else
/// 双分支都赋值——全零 W3099；全局变量不查（C 保证零初始化）。
test "serve_compile_w517_uninit_fixed_paths_no_warn" {
  // ① 先赋值再用
  let s1 = @session.Session::new()
  let (r1, _) = serve_handle(
    s1, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main(void) {\\n    int u;\\n    u = 5;\\n    return u;\\n}\\n\"}}",
  )
  assert_false(
    r1.contains("W3099"),
    msg="先赋值后用不得警（实际：\{r1}）",
  )
  // ② 取址传参写入（&u 经自定义函数——scanf 同形态）
  let s2 = @session.Session::new()
  let (r2, _) = serve_handle(
    s2, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"void wr(int *p);\\nint main(void) {\\n    int u;\\n    wr(&u);\\n    return u;\\n}\\n\"}}",
  )
  assert_false(
    r2.contains("W3099"),
    msg="取址写入不得警（实际：\{r2}）",
  )
  // ③ if-else 双分支都赋值 → 传播
  let s3 = @session.Session::new()
  let (r3, _) = serve_handle(
    s3, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main(void) {\\n    int u;\\n    int c = 1;\\n    if (c) { u = 1; } else { u = 2; }\\n    return u;\\n}\\n\"}}",
  )
  assert_false(
    r3.contains("W3099"),
    msg="双分支全赋值不得警（实际：\{r3}）",
  )
  // ④ 全局变量零初始化是 C 保证——不查
  let s4 = @session.Session::new()
  let (r4, _) = serve_handle(
    s4, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int g;\\nint main(void) {\\n    return g;\\n}\\n\"}}",
  )
  assert_false(
    r4.contains("W3099"),
    msg="全局零初始化保证不得警（实际：\{r4}）",
  )
}
