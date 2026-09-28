// 审阅批 P2/P3 补锚（2026-09-28 用户审阅报告）。
// 转义口径同 serve_run_wbtest（JSON 结构引号 = \"；C 源码内嵌引号 = \\\"）。

///|
test "serve_output_delta_cursor_mid_utf8_byte" {
  // P2 分叉锁锚：cursor 落在多字节字符中间——本侧字节域直接切
  // （oracle 前移到字符边界产空串）；消费方契约 = 只用 total 推进
  // （见 serve_io.mbt 头注分叉登记②）
  let s = @session.Session::new()
  let _ = serve_handle(
    s, "{\"id\":0,\"method\":\"compile\",\"params\":{\"source\":\"#include <stdio.h>\\nint main() { printf(\\\"中\\\"); return 0; }\\n\"}}",
  )
  let _ = serve_handle(s, "{\"id\":1,\"method\":\"run\"}")
  let (r1, _) = serve_handle(
    s, "{\"id\":2,\"method\":\"output.delta\",\"params\":{\"cursor\":1,\"stream\":\"stdout\"}}",
  )
  assert_true(r1.contains("\"total\":3"))
  // 中文字节序列 E4 B8 AD：cursor=1 → 尾 2 字节（Latin-1 折回 2 字符）
  assert_true(
    r1.contains("\"delta\":\"¸­\""),
    msg="中段 cursor 切字节（分叉登记②——oracle 此处前移产空）",
  )
  assert_true(r1.contains("\"cursor\":3"))
}

///|
test "serve_run_not_compiled_early_exit_no_side_effects" {
  // P3-① 独立锚：not_compiled 早退不触发参数域副作用——run 带 input
  // 参数但未编译时 vm.input 不得被替换（早退先于 set_input；与
  // serve_execute_run 内的产物缺失判定构成双判定，可观测面在此）
  let s = @session.Session::new()
  let before = s.vm.input.lines.length()
  let (resp, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"run\",\"params\":{\"input\":\"42\\n\"}}",
  )
  assert_true(resp.contains("\"status\":\"not_compiled\""))
  assert_eq(
    s.vm.input.lines.length(),
    before,
    msg="早退不得动输入态（副作用面与正常路径的分界锚）",
  )
}
