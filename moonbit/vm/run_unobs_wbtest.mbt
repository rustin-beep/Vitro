///| P0 观测落闸锚（#176，2026-11-02）：`run` 全速态三件观测（heatmap /
/// last_accessed_vars / StepEvent vis 事件队列）短路、出口恢复观测态；
/// step 态三件照旧。
///
/// 红→绿：锚一在落闸前**红**（run 后 heatmap 行 1 = 4、vis 队列 1 条、
/// last_accessed 1 条）；锚二是保护锚（落闸前后恒绿——锁「落闸不得误伤
/// step 态」，与锚一同程序同指令流对照）。

///|
/// 共用程序：手动帧（locals_base 0x8000）+ 局部 `i`@4 符号 + vis 行 1 注册 +
/// 四指令 `StepEvent 1 / PushConst 7 / StoreLocal 4 / LoadLocal 4`——loc
/// 全为行 1 file_id 0 ⇒ heatmap 可记；StepEvent 命中 vis 行 ⇒ 入队；
/// Store/LoadLocal ⇒ last_accessed_vars 推入。三件观测面一次覆盖。
fn p0_observed_vm() -> VitroVM {
  let vm = VitroVM::new()
  vm.set_symbols([
    @bytecode.Symbol::{
      name: "i",
      addr: 4U,
      is_local: true,
      ty: @ast.Type::Int(false, false),
      scope_depth: 0,
      func_name: "main",
      decl_line: 1,
    },
  ])
  vm.call_stack.push(CallFrame::{
    return_ip: Some(0),
    locals_base: 0x8000U,
    local_count: 1,
    func_name: "main",
    original_stack_top: 0U,
    caller_line: 0,
    local_buffers: [],
  })
  vm.set_vis_event_lines([(1, 1, "ctx")])
  vm.load_program(
    code_of([
      instr(StepEvent, 1),
      instr(PushConst, 7),
      instr(StoreLocal, 4),
      instr(LoadLocal, 4),
    ]),
  )
  vm
}

///|
/// 锚一：run 全速态三件零记录 + 执行协议（current_line / 步数）不在落闸面
/// + 出口恢复 `observe`（同 VM 再装再逐步可观测——恢复的消费面证据）。
test "p0_run_unobserved_three_gates_off_and_exit_restores" {
  let vm = p0_observed_vm()
  assert_true(vm.observe, msg="缺省观测态")
  let ret = vm.run()
  assert_eq(ret, 7)
  assert_true(vm.error.is_empty())
  // 三件观测在 run 态零记录（落闸前：4 / 1 / 1）
  assert_eq(vm.heatmap_count_at(1), 0UL, msg="run 态 heatmap 不记")
  assert_eq(vm.vis_event_queue.length(), 0, msg="run 态 vis 事件不入队")
  assert_eq(vm.last_accessed_vars.length(), 0, msg="run 态变量访问不记")
  // 执行协议原样：StepEvent 仍更新 current_line；步数照计
  assert_eq(vm.current_line, 1)
  assert_eq(vm.step_count, 4)
  // 出口恢复
  assert_true(vm.observe, msg="run 出口必恢复观测态")
  // 恢复的消费面证据：同 VM 再装同程序逐步 → 三件照记
  vm.load_program(
    code_of([
      instr(StepEvent, 1),
      instr(PushConst, 7),
      instr(StoreLocal, 4),
      instr(LoadLocal, 4),
    ]),
  )
  assert_true(vm.step() is Ok)
  assert_eq(vm.heatmap_count_at(1), 1UL)
  assert_eq(vm.vis_event_queue.length(), 1)
  assert_true(vm.step() is Ok)
  assert_true(vm.step() is Ok)
  assert_eq(vm.last_accessed_vars.length(), 1)
  assert_true(vm.last_accessed_vars[0].access_type is Write)
}

///|
/// 锚二（保护锚）：同程序逐步——三件观测逐字照旧（heatmap 逐步累计 /
/// vis 命中入队 / last_accessed 每步重置并记 Read·Write）。
test "p0_step_observed_three_gates_on" {
  let vm = p0_observed_vm()
  assert_true(vm.step() is Ok) // StepEvent 1
  assert_eq(vm.heatmap_count_at(1), 1UL)
  assert_eq(vm.vis_event_queue.length(), 1)
  assert_eq(vm.vis_event_queue[0].context, "ctx")
  assert_eq(vm.current_line, 1)
  assert_true(vm.step() is Ok) // PushConst 7
  assert_eq(vm.last_accessed_vars.length(), 0)
  assert_true(vm.step() is Ok) // StoreLocal 4 → Write i
  assert_eq(vm.last_accessed_vars.length(), 1)
  assert_eq(vm.last_accessed_vars[0].name, "i")
  assert_true(vm.last_accessed_vars[0].access_type is Write)
  assert_true(vm.step() is Ok) // LoadLocal 4 → Read i（每步重置）
  assert_eq(vm.last_accessed_vars.length(), 1)
  assert_eq(vm.last_accessed_vars[0].name, "i")
  assert_true(vm.last_accessed_vars[0].access_type is Read)
  assert_true(vm.step() is Finished)
  assert_eq(vm.heatmap_count_at(1), 4UL)
  assert_eq(vm.vis_event_queue.length(), 1)
  assert_eq(vm.final_return_value(), 7)
  assert_true(vm.observe)
}
