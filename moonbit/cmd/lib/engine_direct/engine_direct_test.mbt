///|
/// #338 批四（2026-10-27）：engine_direct 首个直接单测——compile_params
/// 的 BUG-A 修复语义（`-` stdin 源不传 filename / 其余传全路径——gateway
/// 侧 base_dir 同目录 include 语义）+ json_escape 转义面。invoke 端到端
/// 真跑属 vitro_cli_smoke 域职责（direct 通道被其多臂对拍覆盖），此处
/// 不重复建设。

///|
test "compile_params_stdin_dash_omits_filename" {
  let ch = @engine_direct.direct_channel()
  let j = (ch.compile_params)("-", "int main(){return 0;}")
  assert_false(j.contains("filename"), msg="stdin 源不得带 filename: \{j}")
  assert_true(j.contains("\"source\""), msg="source 键须在场: \{j}")
}

///|
test "compile_params_named_file_carries_filename" {
  let ch = @engine_direct.direct_channel()
  let j = (ch.compile_params)("demo/main.c", "int main(){return 0;}")
  assert_true(
    j.contains("\"filename\":\"demo/main.c\""),
    msg="filename 须传全路径: \{j}",
  )
}

///|
test "compile_params_json_escapes_source" {
  let ch = @engine_direct.direct_channel()
  // 源码含引号与反斜杠——json_escape 单源（@util）生效面
  let j = (ch.compile_params)("a.c", "char *s = \"x\\n\";")
  assert_true(
    j.contains("\\\"x\\\\n\\\""),
    msg="引号/反斜杠须转义: \{j}",
  )
}
