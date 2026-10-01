///| L9 time_travel·FrameWindow **窗口语义锚族**（S8 批一号二段，2026-10-01）。
///
/// 锚定对象：⑤-5.3 窗口参数协议锚（2_000 / 0.2 / discard=ceil 公式）+
/// U2#1「push 后立即 trim」类型不变量 + 回放断言 S3 A14 形状（2050 步后
/// cache_start_step > 0）+ 坑 ⑥-1/4/5 钳位族三连防线（负参/越窗/倒区间
/// 零 panic）。

///|
/// 测试负载构造（14 字段全量——protocol 无 Default，一次封装多处用；
/// 仅 step_index 变动，其余恒定）。
fn mk_payload(step : Int) -> @protocol.StepPayload {
  {
    step_index: step,
    code_line: 1,
    func_name: "main",
    semantic_label: "",
    algorithm_step: None,
    local_vars: [],
    call_stack: [],
    vis_events: [],
    heatmap_line: 0,
    heatmap_count: 0UL,
    accessed_vars: [],
    array_snapshots: [],
    pointer_snapshots: [],
    root_cause_hint: None,
  }
}

///|
/// 锚一：默认窗口参数 = 协议锚定值（2_000 / 0.2；起点 0、空窗）。
test "frame_window_default_limits" {
  let w = FrameWindow::new()
  assert_eq(w.window_limit(), 2_000)
  assert_eq(w.start_step(), 0)
  assert_true(w.is_empty())
}

///|
/// 锚二：trim 公式精确锚（discard = ceil(len × ratio) clamp [1, len]）——
/// 小窗口 size=10 / ratio=0.2：第 11 帧 push 后 len=11 > 10 → discard =
/// ceil(11×0.2)=ceil(2.2)=3 → len=8、start_step=3。
test "frame_window_trim_semantics" {
  let w = FrameWindow::with_limits(10, 0.2)
  for s = 0; s < 11; s = s + 1 {
    w.push(mk_payload(s))
  }
  assert_eq(w.length(), 8)
  assert_eq(w.start_step(), 3)
  // 窗口首帧 = 步 3（0/1/2 被丢弃）
  let head = w.slice(3, 4)
  assert_eq(head.length(), 1)
  assert_eq(head[0].step_index, 3)
  // 整数积场景：len=10 内不裁；恰好越界 1 帧时 discard=ceil(1.1×…)——
  // 再推 1 帧（len 9→10 不裁）验证边界：10 ≤ 10 不触发
  w.push(mk_payload(11))
  assert_eq(w.length(), 9)
  assert_eq(w.start_step(), 3)
}

///|
/// 锚二补（用户审阅 P3-2，2026-10-01）：**整数积分界锚**——len×ratio 恰为
/// 整数时 `<` 与 `<=` 实现分界（20×0.2=4.0：正确 ceil 得 4；`<=` 突变态
/// 〔floor+1 语义〕得 5 → 多裁一帧 → 本锚红）。锚二族原有样本全为小数积
/// （2.2/10.2/400.2），对 `<`↔`<=` 手误零判别力——协议字段 cache_start_step
/// 会静默偏移，此锚补上分界牙（突变实测有牙：注入 `<=` 后 15 != 16 红）。
test "frame_window_trim_integer_product_boundary" {
  let w = FrameWindow::with_limits(19, 0.2)
  for s = 0; s < 20; s = s + 1 {
    w.push(mk_payload(s))
  }
  assert_eq(w.length(), 16)
  assert_eq(w.start_step(), 4)
}

///|
/// 锚三：U2#1 不变量——**每次 push 后 len ≤ window_size 恒成立**（类型
/// 保证；Rust 侧"重放循环内忘裁 → 63.6GB"形态在结构上不可表达）。
test "frame_window_u21_invariant_push_then_trim" {
  let w = FrameWindow::with_limits(50, 0.2)
  for s = 0; s < 200; s = s + 1 {
    w.push(mk_payload(s))
    assert_true(w.length() <= 50, msg="步 \{s} 后窗口超限")
  }
  // 收尾自洽：start_step + len = 最后推入步号 + 1
  assert_eq(w.start_step() + w.length(), 200)
}

///|
/// 锚四：S3 A14 形状——协议窗口语义（2050 步后 cache_start_step > 0 且
/// 窗口有界；窗口外历史静默丢弃是设计）。
test "frame_window_s3_a14_shape" {
  let w = FrameWindow::new()
  for s = 0; s < 2_050; s = s + 1 {
    w.push(mk_payload(s))
  }
  assert_true(w.start_step() > 0, msg="2050 步后窗口起点必须已推进")
  assert_true(w.length() <= 2_000)
  // 丢完最老帧后，窗口内最小步号 = start_step（步 0 早已不可查）
  let head = w.slice(0, w.start_step())
  assert_eq(head.length(), 0, msg="窗口外历史不可查")
}

///|
/// 锚五：钳位族三连防线（坑 ⑥-1/4/5——负参 seek / 越窗 end / 倒区间，
/// 全部返回空或钳位结果，零 panic 零绕回）。
test "frame_window_slice_clamp_family" {
  let w = FrameWindow::with_limits(10, 0.2)
  // 灌满并触发两次裁剪：len 稳态 < 10
  for s = 0; s < 25; s = s + 1 {
    w.push(mk_payload(s))
  }
  let start = w.start_step()
  let len = w.length()
  assert_true(start > 0)
  // 负 start：钳到窗口起点
  let clamped = w.slice(-100, start + 1)
  assert_eq(clamped.length(), 1)
  assert_eq(clamped[0].step_index, start)
  // 超窗 end：钳到窗口末
  let tail = w.slice(start + len - 1, 999_999)
  assert_eq(tail.length(), 1)
  assert_eq(tail[0].step_index, start + len - 1)
  // 倒区间 / 空窗口
  assert_eq(w.slice(5, 2).length(), 0)
  let empty = FrameWindow::new()
  assert_eq(empty.slice(0, 10).length(), 0)
}

///|
/// 锚六：末帧读口 + 清空复位（reset 连坐通道）。
test "frame_window_last_and_clear" {
  let w = FrameWindow::new()
  assert_true(w.last() is None)
  w.push(mk_payload(7))
  guard w.last() is Some(p) else { fail("last 必须命中") }
  assert_eq(p.step_index, 7)
  w.clear()
  assert_true(w.is_empty())
  assert_eq(w.start_step(), 0)
  assert_true(w.last() is None)
}

// ─────────────────────────────────────────────────────────────────────
// finish_replay 三分支直锚（2026-10-01 审阅 P1 补锚）：重放收尾窗口承载
// 三次历史事故修复（63.6GB 未重置 / R-2026-09-01/02 钳位缺失 panic /
// 越窗记账），但协议默认窗口 2_000 使小 target 下分支全不可达（缺陷
// 形态 A12——锚须放大参数构造可达分支）。
// ─────────────────────────────────────────────────────────────────────

///|
/// 锚七：finish_replay 的 discard 段（want_start > start 时按 min 钳位
// 裁头 + 起点记账）——with_limits(10, 0.2) 推 5 帧后 finish_replay(20)：

///|
/// want_start = 20-10+1 = 11 > start(0)，discard = min(11, 5) = 5 ⇒
/// 清空 + start=5；expected = 20-5+1 = 16 > len(0) 不截尾。
test "frame_window_finish_replay_discard_branch" {
  let w = FrameWindow::with_limits(10, 0.2)
  for i = 0; i < 5; i = i + 1 {
    w.push(mk_payload(i))
  }
  assert_eq(w.start_step(), 0)
  assert_eq(w.length(), 5)
  w.finish_replay(20)
  assert_eq(w.length(), 0, msg="discard=min(11,5)=5 清空")
  assert_eq(
    w.start_step(),
    5,
    msg="起点按实际推进量记账（钳位后 5 而非 11）",
  )
  // expected=16 > len=0：截尾段不动
  assert_true(w.frame_at(5) is None)
}

///|
/// 锚八：finish_replay 的钳位分支（want_start - start > len——seek 目标
/// 远超已有步数，R-2026-09-01/02 事故形态：无钳位的理论 discard 直接
/// 切会越界）——with_limits(10, 0.2) 推 3 帧后 finish_replay(50)：
/// want_start = 41，理论 discard = 41 > len = 3 ⇒ 钳到 3。
test "frame_window_finish_replay_clamp_branch" {
  let w = FrameWindow::with_limits(10, 0.2)
  for i = 0; i < 3; i = i + 1 {
    w.push(mk_payload(i))
  }
  w.finish_replay(50)
  // 钳位：discard = min(41, 3) = 3——清空且不越界，起点 = 0+3
  assert_eq(w.length(), 0)
  assert_eq(w.start_step(), 3)
}

///|
/// 锚九：finish_replay 的截尾段（target 之后的多余帧裁除；discard 段
/// 不触发——want_start 钳 0 后不大于 start）——with_limits(10, 0.2)
/// 推 8 帧后 finish_replay(5)：expected = 5-0+1 = 6 ⇒ pop_back 2。
test "frame_window_finish_replay_truncate_branch" {
  let w = FrameWindow::with_limits(10, 0.2)
  for i = 0; i < 8; i = i + 1 {
    w.push(mk_payload(i))
  }
  w.finish_replay(5)
  assert_eq(w.start_step(), 0, msg="discard 段不触发（want_start 钳 0）")
  assert_eq(w.length(), 6, msg="expected=6 截去 target 后 2 帧")
  guard w.frame_at(5) is Some(p) else { fail("target 帧保留") }
  assert_eq(p.step_index, 5)
  assert_true(w.frame_at(6) is None, msg="target 之后帧裁除")
}

///|
/// 锚十：finish_replay 空窗口幂等（reset_to 后收尾——seek 越窗前置
/// 与收尾的组合形态）。
test "frame_window_finish_replay_empty_noop" {
  let w = FrameWindow::with_limits(10, 0.2)
  w.reset_to(7)
  w.finish_replay(7)
  assert_eq(w.start_step(), 7)
  assert_eq(w.length(), 0)
}
