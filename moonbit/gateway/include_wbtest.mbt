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
  // 未注册走同一 vfs 空表路径——本锚同时锁 wasm 侧行为面；2026-10-05
  // files-vfs 批后本锚语义收窄为「单 source 形态」：files 集合内互引
  // 已可解析，集合外仍 E1021，见 wasm_files_vfs 系锚）
  set_include_reader(fn(_path : String) -> String? { None })
  let (resp, _) = serve_handle(
    session, "{\"id\":2,\"method\":\"compile\",\"params\":{\"source\":\"#include \\\"myinc.h\\\"\\nint main(){ return VALUE; }\\n\",\"filename\":\"d:/x/main.c\"}}",
  )
  assert_true(resp.contains("\"ok\":false"), msg="未注册 ⇒ 编译失败")
  assert_true(resp.contains("E1021"), msg="E1021 not found（wasm 同路径）")
  assert_false(session.compile.compiled)
}

///|
test "wasm_files_vfs_resolves_in_set_quote_include" {
  // wasm 形态 = include_reader 未注册（None）——注意 set_include_reader(
  // None-reader) 落 Some 分支（宿主 provider），对 vfs 分叉不等价，故
  // wbtest 同包直写 include_reader.val（None 即 wasm-gc 出口的真初始态）
  include_reader.val = None
  let (resp, _) = serve_handle(
    session,
    "{\"id\":3,\"method\":\"compile\",\"params\":{\"files\":[" +
    "{\"filename\":\"main.c\",\"source\":\"#include \\\"value.h\\\"\\nint main(){ return VALUE; }\\n\"}," +
    "{\"filename\":\"value.h\",\"source\":\"#define VALUE 7\\n\"}]}}",
  )
  assert_true(
    resp.contains("\"ok\":true"),
    msg="files 集合内 quote-include 真解析",
  )
  assert_true(
    session.compile.compiled,
    msg="宏 VALUE 自 value.h 展开后编译通过",
  )
}

///|
test "wasm_files_vfs_outside_set_still_e1021" {
  // 集合外文件仍 E1021（教学诊断保留：wasm 无文件系统，宁诊断不静默——
  // 勘察 H-5 语义不因 files 注入而松动）
  include_reader.val = None
  let (resp, _) = serve_handle(
    session,
    "{\"id\":4,\"method\":\"compile\",\"params\":{\"files\":[" +
    "{\"filename\":\"main.c\",\"source\":\"#include \\\"nope.h\\\"\\nint main(){ return 0; }\\n\"}]}}",
  )
  assert_true(resp.contains("E1021"), msg="集合外 include 仍 E1021")
  assert_false(session.compile.compiled)
}

///|
test "wasm_files_vfs_header_unit_not_merged" {
  // .h unit 只进 vfs 不进拼接（C 语义对齐：头文件不被"编译"，仅 include
  // 可达）——否则 .h 物理拼接在尾部 + include 点展开 = 双重定义
  //（typedef/全局变量撞重复定义诊断）。锚：typedef 头 + include 展开
  // 编译通过，且 file_ranges 不含 .h 区间
  include_reader.val = None
  let (resp, _) = serve_handle(
    session,
    "{\"id\":6,\"method\":\"compile\",\"params\":{\"files\":[" +
    "{\"filename\":\"main.c\",\"source\":\"#include \\\"t.h\\\"\\nint main(){ struct P p; p.x = 1; return p.x; }\\n\"}," +
    "{\"filename\":\"t.h\",\"source\":\"typedef struct { int x; } P;\\n\"}]}}",
  )
  assert_true(
    resp.contains("\"ok\":true"),
    msg="typedef 头不双重定义（修前红：拼接+展开各一次 P）",
  )
  let has_header_range = session.compile.file_ranges
    .iter()
    .any(r => r.filename == "t.h")
  assert_false(has_header_range, msg=".h unit 不产 file_ranges 区间")
}

///|
test "wasm_files_vfs_subdir_base_dir_chain" {
  // 子目录形态：主文件目录段进 base_dir 候选链（与 CLI 形态 dir_of 语义
  // 对齐）——"sub/main.c" 的 `#include "util.h"` 命中 key "sub/util.h"
  include_reader.val = None
  let (resp, _) = serve_handle(
    session,
    "{\"id\":5,\"method\":\"compile\",\"params\":{\"files\":[" +
    "{\"filename\":\"sub/main.c\",\"source\":\"#include \\\"util.h\\\"\\nint main(){ return U; }\\n\"}," +
    "{\"filename\":\"sub/util.h\",\"source\":\"#define U 5\\n\"}]}}",
  )
  assert_true(
    resp.contains("\"ok\":true"),
    msg="子目录 base_dir 候选链命中",
  )
  assert_true(session.compile.compiled)
}
