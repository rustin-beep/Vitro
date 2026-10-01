// serve dump 族白盒锚（S8 dump 接线批，2026-10-01）：三方法协议面 +
// 错误路径同构 + **只读契约机判锚**（dump 前后 session 状态零变——
// 2026-09-29 契约拍板的可执行形态）。wire 逐字节对拍留批四号
//（protocol_frames 双宿主——本族锁结构面）。

///|
test "serve_dump_ast_ok_path" {
  let s = @session.Session::new()
  let (r, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"ast.dump\",\"params\":{\"source\":\"int main() { return 1; }\\n\"}}",
  )
  assert_true(r.contains("\"ok\":true"))
  assert_true(r.contains("\"parse_error_count\":0"))
  assert_true(r.contains("\"ast\":{\"structs\""))
  assert_true(r.contains("\"stall_count\":0"))
}

///|
test "serve_dump_ast_lex_error_path" {
  let s = @session.Session::new()
  let (r, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"ast.dump\",\"params\":{\"source\":\"int main() { return 1 `$; }\\n\"}}",
  )
  assert_true(r.contains("\"ok\":false"))
  assert_true(r.contains("\"lex_error_count\":"))
  assert_true(r.contains("\"ast\":null"))
  assert_true(r.contains("\"parse_errors\":[]"))
}

///|
test "serve_dump_ast_parse_error_path" {
  let s = @session.Session::new()
  let (r, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"ast.dump\",\"params\":{\"source\":\"int main() { int a = ; }\\n\"}}",
  )
  // Rust 语义：ok 只随 program 是否 Some（错误恢复的占位 AST 同 ok:true
  // 且 parse_error_count 非空——锁明细而非极性；错误恢复可级联多报，
  // 不锁计数）
  assert_true(r.contains("\"parse_error_count\":"))
  assert_true(r.contains("\"parse_errors\":[{\"code\""))
  // 诊断明细四字段（E2 面：code/line/column/message 保序）
  assert_true(r.contains("\"code\""))
  assert_true(r.contains("\"line\""))
  assert_true(r.contains("\"column\""))
  assert_true(r.contains("\"message\""))
}

///|
test "serve_dump_typeck_ok_and_type_error" {
  let s = @session.Session::new()
  let (ok, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"typeck.dump\",\"params\":{\"source\":\"int main() { int a = 1; return a; }\\n\"}}",
  )
  assert_true(ok.contains("\"ok\":true"))
  assert_true(ok.contains("\"typed_ast\":{\"structs\""))
  assert_true(ok.contains("\"type_errors\":[]"))
  let (err, _) = serve_handle(
    s, "{\"id\":2,\"method\":\"typeck.dump\",\"params\":{\"source\":\"int main() { return x; }\\n\"}}",
  )
  assert_true(
    err.contains("\"ok\":true"),
    msg="类型错非阻断（type_errors 非空仍带 typed_ast）",
  )
  assert_true(err.contains("\"type_errors\":[{\"code\""))
}

///|
test "serve_dump_symbols_table" {
  let s = @session.Session::new()
  let (r, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"symbols.dump\",\"params\":{\"source\":\"int g = 5;\\nint main() { int i = 1; return g + i; }\\n\"}}",
  )
  assert_true(r.contains("\"ok\":true"))
  assert_true(r.contains("\"count\":"))
  // 全局 g 与局部 i 均入表（name/addr/is_local/decl_line 四字段）
  assert_true(r.contains("\"name\":\"g\""))
  assert_true(r.contains("\"name\":\"i\""))
  assert_true(r.contains("\"is_local\":false"))
  assert_true(r.contains("\"is_local\":true"))
  assert_true(r.contains("\"decl_line\""))
}

///|
test "serve_dump_missing_source_protocol_error" {
  let s = @session.Session::new()
  for m in ["ast.dump", "typeck.dump", "symbols.dump"] {
    let (r, _) = serve_handle(s, "{\"id\":1,\"method\":\"\{m}\"}")
    assert_true(r.contains("\"kind\":\"protocol\""))
    assert_true(r.contains("需要 params.source"))
  }
}

///|
test "serve_dump_readonly_contract" {
  // 只读契约机判锚（2026-09-29 拍板）：dump 前后 session 编译态/诊断面
  // 零变——oracle 的 run_multi_file_pipeline 副作用（写 session 诊断）
  // 不照搬（已知限制 ④表）
  let s = @session.Session::new()
  // 先建立非平凡会话态：一次失败编译（诊断非空 + compiled=false）
  ignore(
    serve_handle(
      s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main() { return ; }\\n\"}}",
    ),
  )
  let diags_before = s.compile.diagnostics.length()
  let compiled_before = s.compile.compiled
  assert_true(diags_before > 0, msg="前置：编译失败诊断非空")
  assert_false(compiled_before)
  // 三 dump 全走一遍（成功 + 失败路径混合）
  ignore(
    serve_handle(
      s, "{\"id\":2,\"method\":\"ast.dump\",\"params\":{\"source\":\"int main() { return ; }\\n\"}}",
    ),
  )
  ignore(
    serve_handle(
      s, "{\"id\":3,\"method\":\"typeck.dump\",\"params\":{\"source\":\"int main() { return ; }\\n\"}}",
    ),
  )
  ignore(
    serve_handle(
      s, "{\"id\":4,\"method\":\"symbols.dump\",\"params\":{\"source\":\"int g = 1;\\nint main() { return g; }\\n\"}}",
    ),
  )
  // 会话态零变（诊断数 / compiled / 产物——dump 不写）
  assert_eq(s.compile.diagnostics.length(), diags_before)
  assert_eq(s.compile.compiled, compiled_before)
  assert_true(s.compile.output is None, msg="symbols.dump 不落产物")
}
