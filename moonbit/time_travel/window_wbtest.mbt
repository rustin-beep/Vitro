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
