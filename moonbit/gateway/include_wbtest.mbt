// quote-include 宿主形态分叉锚（2026-09-29 审阅 P2 补——此前修复零锚：
// 突变回 vfs 空表缺陷形态时 58/58 全绿 + serve_smoke 全绿，防线全盲）。
// 双分支锁定：注册 reader ⇒ include 真解析（宏链进 trace）；未注册/
// None-reader ⇒ E1021（wasm-gc 形态同路径）。锚内自恢复（注入 None-
// reader 等效未注册——无撤销接口，见 include_reader 注释）。

///|
test "include_reader_registered_parses_local_header" {
  set_include_reader(fn(path : String) -> String? {
    if path.has_suffix("myinc.h") {
      Some("#define VALUE 7\n")
    } else {
      None
    }
  })
  let (resp, _) = serve_handle(
    session, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"#include \\\"myinc.h\\\"\\nint main(){ return VALUE; }\\n\",\"filename\":\"d:/x/main.c\"}}",
  )
  assert_true(
    resp.contains("\"ok\":true"),
    msg="注册形态 include 真解析",
  )
  assert_true(
    session.compile.compiled,
    msg="编译成功（宏 VALUE 展开后 return 7）",
  )
  assert_true(
    session.compile.preprocessor_trace.length() > 0,
    msg="宏展开链进 preprocessor_trace",
  )
  // 自恢复：None-reader 等效未注册（后续锚不受全局状态污染）
  set_include_reader(fn(_path : String) -> String? { None })
}

///|
test "include_reader_absent_reports_e1021" {
  // None-reader ⇒ HostIncludeProvider NotFound ⇒ E1021（wasm-gc 形态
  // 未注册走同一 vfs 空表路径——本锚同时锁 wasm 侧行为面）
  set_include_reader(fn(_path : String) -> String? { None })
  let (resp, _) = serve_handle(
    session, "{\"id\":2,\"method\":\"compile\",\"params\":{\"source\":\"#include \\\"myinc.h\\\"\\nint main(){ return VALUE; }\\n\",\"filename\":\"d:/x/main.c\"}}",
  )
  assert_true(resp.contains("\"ok\":false"), msg="未注册 ⇒ 编译失败")
  assert_true(resp.contains("E1021"), msg="E1021 not found（wasm 同路径）")
  assert_false(session.compile.compiled)
}
