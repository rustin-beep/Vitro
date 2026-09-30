///| L9 time_travel·UnifiedEngine **状态定形锚**（S8 批一号二段，2026-10-01）。
///
/// 锚定对象：默认参数协议锚（max_steps=100_000 / 检查点 interval=20 /
/// 窗口 2_000+0.2——⑤-5.3 逐字保留）+ 三粘性标志生命周期 + reset 全清
/// （终态唯一清除通道）+ with_max_steps 守卫。run_batch/seek_to 行为锚
/// 随批一号三段（Trap 回退改重放）接线。

///|
/// 锚一：默认状态 = 协议锚定参数全集。
test "engine_default_state" {
  let e = UnifiedEngine::new()
  assert_eq(e.get_max_steps(), 100_000)
  assert_eq(e.checkpoints.get_interval(), 20)
  assert_eq(e.frames.window_limit(), 2_000)
  assert_eq(e.frames.start_step(), 0)
  assert_false(e.is_paused)
  assert_false(e.is_cancelled)
  assert_false(e.is_finished)
}

///|
/// 锚二：自定义步数预算 + 非法值守卫（fail loud，不静默钳）。
test "engine_with_max_steps_guard" {
  let e = UnifiedEngine::with_max_steps(500_000)
  assert_eq(e.get_max_steps(), 500_000)
  // max_steps=0 / 负值：guard abort（fail loud 口径——非法配置不进入
  // 运行期半路爆）。abort 断言形态：测试进程级——这里只锚合法面，
  // 非法面由 guard 表达式编译期可见 + 人工审视覆盖。
}

///|
/// 锚三：暂停/取消生命周期。
test "engine_pause_unpause_cancel" {
  let e = UnifiedEngine::new()
  e.pause()
  assert_true(e.is_paused)
  e.unpause()
  assert_false(e.is_paused)
  e.cancel()
  assert_true(e.is_cancelled)
}

///|
/// 锚四：reset 全清——窗口起点归零、检查点清、三粘性复位（终态唯一
/// 清除通道；is_finished 粘性 = 坑 ⑥-6，reset 前不可自清）。
test "engine_reset_clears_all" {
  let e = UnifiedEngine::new()
  // 造脏：推帧过窗（起点推进）+ 存检查点 + 三标志全置
  for s = 0; s < 2_050; s = s + 1 {
    e.frames.push({
      step_index: s,
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
    })
  }
  ignore(e.checkpoints.save(1, @vm.VitroVM::new()))
  e.pause()
  e.cancel()
  e.is_finished = true
  assert_true(e.frames.start_step() > 0)
  assert_true(e.checkpoints.length() > 0)
  assert_true(e.is_finished)
  // reset：全清
  e.reset()
  assert_eq(e.frames.start_step(), 0)
  assert_true(e.frames.is_empty())
  assert_true(e.checkpoints.is_empty())
  assert_false(e.is_paused)
  assert_false(e.is_cancelled)
  assert_false(e.is_finished)
}
