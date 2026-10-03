// serve run 白盒锚（S7 批三号二段）：execute_run 等价五步 + 六字段出口 +
// 「2000 步真停」端到端锚（会话批登记义务——Rust 事故形态的对照锚：
// capi/serve 曾在 compile 前设置的 max_steps 被静默丢弃、程序跑满默认
// 1000 万步；本侧 vm 非 Option + 装载通道禁写纪律下结构上不可丢弃，
// 锁行为防回归）。
// 字符串转义口径：JSON 结构引号 = `\"`；C 源码内嵌引号（JSON 值域）=
// `\\\"`（JSON `\"` 两字符）；`\\n` = C 源码换行。

///|
test "serve_run_not_compiled_frame" {
  let s = @session.Session::new()
  let (resp, _) = serve_handle(s, "{\"id\":1,\"method\":\"run\"}")
  assert_true(
    resp.contains("\"ok\":true"),
    msg="外层帧成功（内层 ok:false）",
  )
  assert_true(resp.contains("\"status\":\"not_compiled\""))
  assert_true(resp.contains("程序尚未编译"))
  assert_true(resp.contains("\"steps_executed\":0"))
}

///|
test "serve_run_hello_finished" {
  let s = @session.Session::new()
  let (_, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"#include <stdio.h>\\nint main() { printf(\\\"hi\\\"); return 42; }\\n\"}}",
  )
  let (resp, _) = serve_handle(s, "{\"id\":2,\"method\":\"run\"}")
  assert_true(resp.contains("\"status\":\"finished\""))
  assert_true(resp.contains("\"return_value\":42"))
  assert_true(resp.contains("\"trap\":\"\""))
  assert_true(resp.contains("\"waiting_input\":false"))
  assert_true(s.vm.step_count > 0, msg="步数计数非零")
  // stdout 通道（OutputLog Bytes 化）
  assert_true(s.vm.output.len_of(@host.OutputKind::Stdout) >= 2)
  // E-P1-5：运行完成附注走 note 通道
  assert_true(
    s.vm.output.has_note(@utf8.encode("程序运行完成，返回值：42\n")),
    msg="完成附注在 note 通道",
  )
}

///|
test "serve_run_max_steps_2000_true_stop" {
  // **「2000 步真停」端到端锚**（会话批遗留义务）：config.set 写在
  // compile **之前** → run 真停在 2000 步（Rust 事故：vm None 时配置
  // 静默丢弃跑满 1000 万步——session.rs:117 头注；本侧单一写入口 +
  // setup 内部 reset 保留 max_steps，结构上不可丢弃）
  let s = @session.Session::new()
  let (cfg_resp, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"config.set\",\"params\":{\"max_steps\":2000}}",
  )
  assert_true(cfg_resp.contains("\"max_steps\":2000"))
  let (_, _) = serve_handle(
    s, "{\"id\":2,\"method\":\"compile\",\"params\":{\"source\":\"int main() { while (1) { } return 0; }\\n\"}}",
  )
  let (resp, _) = serve_handle(s, "{\"id\":3,\"method\":\"run\"}")
  assert_true(
    resp.contains("\"steps_executed\":2000"),
    msg="必须真停在第 2000 步",
  )
  assert_true(
    resp.contains("\"status\":\"trap\""),
    msg="超步数按无限循环 trap 报告",
  )
  assert_true(resp.contains("\"ok\":false"))
}

///|
test "serve_run_waiting_input_interactive_default" {
  // 输入模式默认 Interactive（Rust InputMode #[default] 首变体）：
  // scanf 无输入 → waiting_input 而非 EOF
  let s = @session.Session::new()
  let (_, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"#include <stdio.h>\\nint main() { int n; scanf(\\\"%d\\\", &n); return 0; }\\n\"}}",
  )
  let (resp, _) = serve_handle(s, "{\"id\":2,\"method\":\"run\"}")
  assert_true(resp.contains("\"status\":\"waiting_input\""))
  assert_true(resp.contains("\"waiting_input\":true"))
  assert_true(s.vm.waiting_input)
}

///|
test "serve_run_input_param_feeds_scanf" {
  // run 帧带 input 参数（覆盖式喂入 + 游标重置）：scanf 读到 42
  let s = @session.Session::new()
  let (_, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"#include <stdio.h>\\nint main() { int n; scanf(\\\"%d\\\", &n); printf(\\\"got %d\\\", n); return 0; }\\n\"}}",
  )
  let (resp, _) = serve_handle(
    s, "{\"id\":2,\"method\":\"run\",\"params\":{\"input\":\"42\\n\"}}",
  )
  assert_true(resp.contains("\"status\":\"finished\""), msg="喂入后跑完")
  assert_true(
    stdout_text(s).contains("got 42"),
    msg="scanf 必须读到喂入值",
  )
}

///|
test "serve_run_waiting_then_input_resumes" {
  // is_resume 语义：waiting 态的 run 带 input = 喂入续跑（input.feed 的
  // 方法帧形态，本段经 run 通道承载）——参数回推 + ip 回退已就位
  let s = @session.Session::new()
  let (_, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"#include <stdio.h>\\nint main() { int n; scanf(\\\"%d\\\", &n); printf(\\\"got %d\\\", n); return 0; }\\n\"}}",
  )
  let (resp1, _) = serve_handle(s, "{\"id\":2,\"method\":\"run\"}")
  assert_true(resp1.contains("\"waiting_input\":true"))
  let (resp2, _) = serve_handle(
    s, "{\"id\":3,\"method\":\"run\",\"params\":{\"input\":\"7\\n\"}}",
  )
  assert_true(resp2.contains("\"status\":\"finished\""), msg="续跑完成")
  assert_true(
    resp2.contains("\"waiting_input\":false"),
    msg="续跑后旗回落",
  )
  assert_true(stdout_text(s).contains("got 7"))
}

///|
test "serve_run_argv_param_and_persistence" {
  // argv 参数传递 + 跨 run 存活（Rust session.runtime.argv 语义）：
  // 二次 run 不带 argv 沿用首值
  let s = @session.Session::new()
  let (_, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"#include <stdio.h>\\nint main(int argc, char** argv) { printf(\\\"%d\\\", argc); return 0; }\\n\"}}",
  )
  let (_, _) = serve_handle(
    s, "{\"id\":2,\"method\":\"run\",\"params\":{\"argv\":[\"prog\",\"a\"]}}",
  )
  assert_eq(stdout_text(s), "2", msg="argc = 2（prog + a）")
  // 二次 run 无 argv：沿用
  let (_, _) = serve_handle(s, "{\"id\":3,\"method\":\"run\"}")
  assert_eq(stdout_text(s), "2", msg="argv 跨 run 存活")
}

///|
test "serve_run_trap_zero_division" {
  let s = @session.Session::new()
  let (_, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main() { int z = 0; return 1 / z; }\\n\"}}",
  )
  let (resp, _) = serve_handle(s, "{\"id\":2,\"method\":\"run\"}")
  assert_true(resp.contains("\"status\":\"trap\""))
  assert_true(resp.contains("\"ok\":false"))
  assert_false(resp.contains("\"trap\":\"\""), msg="trap 串非空")
}

///|
test "serve_run_max_steps_in_run_frame" {
  // run 帧内联 config.set（Rust run 臂调 serve_apply_config(params) 同形）
  let s = @session.Session::new()
  let (_, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main() { while (1) { } return 0; }\\n\"}}",
  )
  let (resp, _) = serve_handle(
    s, "{\"id\":2,\"method\":\"run\",\"params\":{\"max_steps\":100}}",
  )
  assert_true(
    resp.contains("\"steps_executed\":100"),
    msg="run 帧内联配置生效",
  )
}

///|
test "serve_run_batch_input_mode_eof" {
  // batch_input:true 时输入耗尽走 EOF（Batch 模式——判分口径）而非等待
  let s = @session.Session::new()
  let (_, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"#include <stdio.h>\\nint main() { int n; int r = scanf(\\\"%d\\\", &n); printf(\\\"r=%d\\\", r); return 0; }\\n\"}}",
  )
  let (resp, _) = serve_handle(
    s, "{\"id\":2,\"method\":\"run\",\"params\":{\"batch_input\":true}}",
  )
  assert_true(
    resp.contains("\"status\":\"finished\""),
    msg="Batch 模式 EOF 不等待",
  )
  assert_true(stdout_text(s).contains("r=-1"), msg="scanf 返 EOF（-1）")
}

///|
/// stdout 通道拼接（Bytes → Latin-1 文本形态——Go 侧归一同口径）。
fn stdout_text(s : @session.Session) -> String {
  let buf = StringBuilder()
  for chunk in s.vm.output.chunks_of(@host.OutputKind::Stdout) {
    for j = 0; j < chunk.length(); j = j + 1 {
      buf.write_char(chunk[j].to_int().unsafe_to_char())
    }
  }
  buf.to_string()
}

///|
test "serve_run_leak_report_note_channel" {
  // S8 analysis 片·堆教学附注（oracle session_ops.rs append_leak_report
  // 照搬）：malloc 不 free → run 完成 → note 通道追加泄漏报告（此前
  // 分叉①登记「随 S8 analysis 片」未接线）。文案逐字对齐 oracle。
  let s = @session.Session::new()
  let (_, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"#include <stdlib.h>\\nint main() { int* p = malloc(16); *p = 1; return 0; }\\n\"}}",
  )
  let (resp, _) = serve_handle(s, "{\"id\":2,\"method\":\"run\"}")
  assert_true(resp.contains("\"status\":\"finished\""), msg="run 须完成")
  // 泄漏报告逐项：标题/计数/逐条（行号+函数名+字节数+地址）/教学提示。
  // 断言走 has_note 字节级比对（push_note_str 逐行成段，段落精确等值）
  // ——勿用 chunks 逐字节 to_char 重建（UTF-8 折回 Latin-1 形态，
  // contains 永失配——本锚首版实锤；serve_io 分叉登记同源）
  assert_true(
    s.vm.output.has_note(
      @utf8.encode("\n===== 内存泄漏检测报告 =====\n"),
    ),
    msg="报告标题（首行带前导 \\n 分隔——oracle 同款；push_note 补尾 \\n）",
  )
  assert_true(
    s.vm.output.has_note(
      @utf8.encode("发现 1 处未释放的堆内存，共 16 字节：\n"),
    ),
    msg="计数行",
  )
  assert_true(
    s.vm.output.has_note(
      @utf8.encode(
        "  • 第 2 行的 malloc 分配了 16 字节 (addr=0x5018)，未被 free\n",
      ),
    ),
    msg="逐条行（行号/函数/字节/地址全字段——addr 为 oracle {:04X} 最少 4 位形态，非恒 8 位）",
  )
  assert_true(
    s.vm.output.has_note(
      @utf8.encode(
        "💡 提示：在 C 语言中，malloc 分配的内存需要对应 free 释放，否则会造成内存泄漏。\n",
      ),
    ),
    msg="教学提示行",
  )
}
