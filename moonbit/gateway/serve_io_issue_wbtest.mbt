///|
/// #85（2026-10-14 报/修）：steps_executed 比真实指令数多出「续跑次数」
/// ——CallHost waiting 中断时 ip 回退但 step_count 不回退，resume 重执行
/// 同一指令双计。等价锚：同程序同输入，一次喂 vs 分两次喂（run→feed），
/// 面板数字必须相同（issue 原话「喂法不同面板数字就不同」）。
test "issue85_feed_resume_step_count_no_double" {
  // S1：一次喂到位
  let s1 = @session.Session::new()
  let (_, _) = serve_handle(
    s1, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"#include <stdio.h>\\nint main() { int n; scanf(\\\"%d\\\", &n); printf(\\\"%d\\\", n); return 0; }\\n\"}}",
  )
  let (r1, _) = serve_handle(
    s1, "{\"id\":2,\"method\":\"run\",\"params\":{\"input\":\"42\\n\"}}",
  )
  let n1 = steps_of(r1)
  // S2：run 到 waiting → feed 续跑
  let s2 = @session.Session::new()
  let (_, _) = serve_handle(
    s2, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"#include <stdio.h>\\nint main() { int n; scanf(\\\"%d\\\", &n); printf(\\\"%d\\\", n); return 0; }\\n\"}}",
  )
  let (_, _) = serve_handle(s2, "{\"id\":2,\"method\":\"run\"}")
  let (r2, _) = serve_handle(
    s2, "{\"id\":3,\"method\":\"input.feed\",\"params\":{\"text\":\"42\\n\"}}",
  )
  let n2 = steps_of(r2)
  assert_true(n1 > 0, msg="S1 应有真实计数")
  assert_true(r2.contains("\"status\":\"finished\""), msg="S2 续跑完成")
  assert_eq(n2, n1, msg="喂法不同面板数字必须相同（旧多 +1）")
}

///|
fn steps_of(resp : String) -> Int32 {
  match find_key(resp, "\"steps_executed\":", 0) {
    Some(p) => parse_digits_at(resp, p)
    None => -1
  }
}

///|
/// 在 s[offs..] 中找 key，返回（offs + key 起位 + key 长度）——即数字
/// 期望起始位；未找到 None。
fn find_key(s : String, key : String, offs : Int32) -> Int32? {
  let tail = s.substring(start=offs)
  match tail.find(key) {
    Some(p) => Some(offs + p + key.length())
    None => None
  }
}

///|
/// 从 s[start..] 手写解析非负整数前缀（无匹配 0）。
fn parse_digits_at(s : String, start : Int32) -> Int32 {
  let mut v = 0
  let mut i = start
  while i < s.length() && s[i] >= '0' && s[i] <= '9' {
    v = v * 10 + (s[i].to_int() - '0'.to_int())
    i = i + 1
  }
  v
}

///|
/// #86（2026-10-14 报/修）：步进会话中 input.feed 续跑——旧走 vm.run()
/// 全速绕过 engine，续跑指令零帧 + 尾帧 step_index 越界（帧流断档）。
/// 修复后 feed 走 engine 通道：帧流连续（max(step_index) == 帧数-1）。
test "issue86_step_session_feed_frames_continuous" {
  let s = @session.Session::new()
  let (_, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"#include <stdio.h>\\nint main() { int n; scanf(\\\"%d\\\", &n); printf(\\\"%d\\\", n); return 0; }\\n\"}}",
  )
  let (_, _) = serve_handle(s, "{\"id\":2,\"method\":\"step.begin\"}")
  // 步进到 waiting
  let mut waiting = false
  for i = 0; i < 40; i = i + 1 {
    let (r, _) = serve_handle(s, "{\"id\":3,\"method\":\"step.next\"}")
    if r.contains("\"waiting_input\":true") {
      waiting = true
      break
    }
    if r.contains("\"finished\":true") {
      break
    }
  }
  assert_true(waiting, msg="步进应达 waiting_input")
  // feed 续跑（步进会话活跃）
  let (rf, _) = serve_handle(
    s, "{\"id\":4,\"method\":\"input.feed\",\"params\":{\"text\":\"42\\n\"}}",
  )
  assert_true(rf.contains("\"status\":\"finished\""), msg="feed 续跑完成")
  // 冲刷缓冲（feed 走 engine 后已终态——step.next 冲出剩余帧）
  let _ = serve_handle(s, "{\"id\":5,\"method\":\"step.next\"}")
  // 帧流连续性：payload.get 全量帧 max(step_index) == 帧数-1
  let (rp, _) = serve_handle(
    s, "{\"id\":6,\"method\":\"payload.get\",\"params\":{\"start\":0,\"end\":9999}}",
  )
  let idxs = step_indexes_of(rp)
  assert_true(idxs.length() > 12, msg="帧数应含续跑段（>12）")
  let mut mx = -1
  for v in idxs {
    if v > mx {
      mx = v
    }
  }
  // 连续性语义：同一条 CallHost 指令的 waiting 帧 + 完成帧共用一个
  // step_index（两次状态投影、非两条指令）——合法重复恰一处；断言面 =
  // 去重后 0..max 连续（无断档无越界跳号）
  let seen : Set[Int32] = Set([])
  for v in idxs {
    seen.add(v)
  }
  let mut gap = -1
  for k = 0; k <= mx; k = k + 1 {
    if !seen.contains(k) {
      gap = k
      break
    }
  }
  assert_eq(
    gap,
    -1,
    msg="存在断档 step_index（去重后 0..max 应连续）",
  )
  assert_eq(
    mx,
    idxs.length() - 2,
    msg="恰一处 waiting/完成重复帧（帧数 = max+2）",
  )
}

///|
/// 从 payload.get 响应抽取帧 step_index 数组（对 "step_index":N 逐个提取）。
fn step_indexes_of(resp : String) -> Array[Int32] {
  let out : Array[Int32] = []
  let key = "\"step_index\":"
  let mut from = 0
  while true {
    match find_key(resp, key, from) {
      Some(p) => {
        out.push(parse_digits_at(resp, p))
        from = p
      }
      None => break
    }
  }
  out
}

///|
/// #88（2026-10-14 报/修）：交互模式 EOF 口——feed{eof:true} 置 InputState
/// EOF 粘滞（set_eof 单源：游标推底 + 粘滞），scanf 返回 -1 →
/// while(scanf!=EOF) 收尾 finished。
test "issue88_feed_eof_terminates_scanf_loop" {
  let s = @session.Session::new()
  let (_, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"#include <stdio.h>\\nint main() { int n, s = 0; while (scanf(\\\"%d\\\", &n) != EOF) { s += n; } printf(\\\"sum %d\\\", s); return 0; }\\n\"}}",
  )
  let (r1, _) = serve_handle(s, "{\"id\":2,\"method\":\"run\"}")
  assert_true(r1.contains("\"waiting_input\":true"), msg="scanf 等待")
  let (r2, _) = serve_handle(
    s, "{\"id\":3,\"method\":\"input.feed\",\"params\":{\"text\":\"10 20\\n\"}}",
  )
  assert_true(
    r2.contains("\"waiting_input\":true"),
    msg="耗尽后再等（EOF 未置）",
  )
  let (r3, _) = serve_handle(
    s, "{\"id\":4,\"method\":\"input.feed\",\"params\":{\"eof\":true}}",
  )
  assert_true(r3.contains("\"status\":\"finished\""), msg="EOF 后收尾")
  assert_true(stdout_text(s).contains("sum 30"), msg="累计正确")
}

///|
/// #91（2026-10-14 报/修）：stdout 16MiB 预算硬顶静默截断——run 帧报
/// finished 无任何信号（截断注记在 note 通道、dropped 计数在
/// output.delta 帧，判分方不拉不见）。修复：run/feed 帧追加
/// output_truncated 位（dropped>0；协议「只增不改」）+ config 通道
/// output_budget 键（会话级可调，锚可小预算快测；clamp [4KB, 16MB]）。
test "issue91_run_frame_output_truncated_bit" {
  let s = @session.Session::new()
  let (_, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"#include <stdio.h>\\nint main() { for (int i = 0; i < 3000; i++) printf(\\\"abcdefgh\\\"); return 0; }\\n\"}}",
  )
  // 小预算（3000*8=24000 字节 > 4096 预算 → 必截断）
  let (rc, _) = serve_handle(
    s, "{\"id\":2,\"method\":\"config.set\",\"params\":{\"output_budget\":4096}}",
  )
  assert_true(
    rc.contains("\"output_budget\":4096"),
    msg="config 回显新键现值",
  )
  let (r, _) = serve_handle(s, "{\"id\":3,\"method\":\"run\"}")
  assert_true(
    r.contains("\"status\":\"finished\""),
    msg="小预算不影响完成态",
  )
  assert_true(
    r.contains("\"output_truncated\":true"),
    msg="run 帧带截断信号（旧静默）",
  )
  // stdout 通道总量被预算封顶
  let (ro, _) = serve_handle(
    s, "{\"id\":4,\"method\":\"output.delta\",\"params\":{\"stream\":\"stdout\"}}",
  )
  assert_true(
    ro.contains("\"total\":4096"),
    msg="stdout 总量=预算值（丢最旧保最新）",
  )
}

///|
/// #105（2026-10-14 报/修）：config.set 对未知键静默丢弃（实测 input_mode_batch 写入被吞、get 回显恒 false）——与 #91 同族的「静默骗人」形态。修复两面：input_mode_batch 真支持（写 runtime_batch + 即时应用）；其余未知键 fail loud（serve_param_err 报错即文档，#68 单源）。
test "issue105_config_set_unknown_key_fail_loud" {
  let s = @session.Session::new()
  let (_, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"#include <stdio.h>\\nint main() { int n, s = 0; while (scanf(\\\"%d\\\", &n) != EOF) { s += n; } printf(\\\"sum %d\\\", s); return 0; }\\n\"}}",
  )
  // input_mode_batch 真支持：写入即生效（scanf 耗尽走 EOF 不再等待）
  let (r1, _) = serve_handle(
    s, "{\"id\":2,\"method\":\"config.set\",\"params\":{\"input_mode_batch\":true}}",
  )
  assert_true(
    r1.contains("\"input_mode_batch\":true"),
    msg="batch 写入回显",
  )
  let (r2, _) = serve_handle(s, "{\"id\":3,\"method\":\"run\"}")
  assert_true(
    r2.contains("\"status\":\"finished\""),
    msg="batch 模式下 scanf 耗尽即 EOF 收尾（旧 waiting 死等）",
  )
  // 未知键 fail loud
  let s2 = @session.Session::new()
  let (r3, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"config.set\",\"params\":{\"nosuch_key\":1}}",
  )
  assert_true(
    r3.contains("\"ok\":false"),
    msg="未知键报错（旧静默吞）",
  )
  assert_true(r3.contains("nosuch_key"), msg="报文点名未知键")
  assert_true(
    r3.contains("input_mode_batch"),
    msg="expected 形状含合法键清单（报错即文档）",
  )
  // 反例锚：合法键照常
  let (r4, _) = serve_handle(
    s, "{\"id\":2,\"method\":\"config.set\",\"params\":{\"max_steps\":123}}",
  )
  assert_true(r4.contains("\"ok\":true"), msg="合法键照常")
  assert_true(r4.contains("\"max_steps\":123"), msg="现值回显")
}

///|
/// #88 审阅 P2 补锚（2026-10-15）：同批改了 scanf 与 getchar 两处 eof
/// 前置，锚只埋 scanf——getchar eof 前置整段删 110/110 假绿（审阅突变
/// 实证：突变态 waiting 死等）。本锚锁 getchar 形态。**getchar 语义与
/// scanf 分叉**：空流（Interactive 无输入）不等待——可用性检查耗尽即
/// EOF（host_getchar 跨行扫描 None 分支）；eof 粘滞锚用「先喂文本再
/// eof」续跑形态。
test "issue88_getchar_eof_anchor" {
  let s = @session.Session::new()
  let (_, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"#include <stdio.h>\\nint main() { int c, n = 0; while ((c = getchar()) != EOF) { if (c >= 48 && c <= 57) n++; } printf(\\\"digits %d\\\", n); return 0; }\\n\"}}",
  )
  let (_, _) = serve_handle(s, "{\"id\":2,\"method\":\"run\"}")
  let (r2, _) = serve_handle(
    s, "{\"id\":3,\"method\":\"input.feed\",\"params\":{\"text\":\"a1b2\\n\"}}",
  )
  let (r3, _) = serve_handle(
    s, "{\"id\":4,\"method\":\"input.feed\",\"params\":{\"eof\":true}}",
  )
  assert_true(
    r3.contains("\"status\":\"finished\""),
    msg="getchar EOF 后收尾（旧 eof 前置缺失时死等）",
  )
  assert_true(
    stdout_text(s).contains("digits 2"),
    msg="计数正确（a1b2 恰 2 数字——getchar 的 eof 前置参与收尾）",
  )
  ignore(r2)
}
