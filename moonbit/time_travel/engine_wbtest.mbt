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
// ─────────────────────────────────────────────────────────────────────
// 三段-c 锚（2026-10-01）：run_batch · seek_to 行为面——含 ⑤-5.1 Trap 回退
// 专项（回退态 + trap 帧 step_index）与越窗 seek 往返相等。
// ─────────────────────────────────────────────────────────────────────

///|
/// 指令流 helper（行号可指定——帧 code_line 维度锚需要交错行号）。
fn instr_at(
  op : @opcode.OpCode,
  operand : Int,
  line : Int,
) -> @opcode.Instruction {
  @opcode.Instruction::new(op, operand, @source.SourceLoc::new(line, 1))
}

///|
/// 源码行供给（FakeProvider——行文本只需非空即可走行号兜底标签）。
struct FakeProvider {
  lines : Map[Int, String]
}

///|
impl SourceLineProvider for FakeProvider with fn source_line_at(
  self : FakeProvider,
  line : Int,
) -> String? {
  self.lines.get(line)
}

///|
fn fake_src() -> FakeProvider {
  let m : Map[Int, String] = Map([])
  m.set(1, "int acc = 0;")
  m.set(2, "acc += 1;")
  m.set(3, "return acc;")
  { lines: m, }
}

///|
/// 程序：StepEvent/Nop 交替 ×n 步（行号 1/2 交错——vm 的 current_line
/// 由 StepEvent 指令驱动〔编译器发射形态〕，纯 Nop 流恒 0；code_line 与
/// 行末去重锚需要交错行号面）。
fn nop_program(n : Int) -> Array[@opcode.Instruction] {
  let out : Array[@opcode.Instruction] = []
  for i = 0; i < n; i = i + 1 {
    let line = 1 + i % 3
    if i % 2 == 0 {
      out.push(instr_at(@opcode.StepEvent, line, line))
    } else {
      out.push(instr_at(@opcode.Nop, 0, line))
    }
  }
  out
}

///|
/// 锚 A：run_batch 基本流——10 指令程序分批跑完：帧数 = 10+1（末次
/// step 返回 Finished 且 collect 终帧）、step_index 连续、终结标志置位。
test "engine_run_batch_basic_flow" {
  let vm = @vm.VitroVM::new()
  vm.load_program(nop_program(10))
  let e = UnifiedEngine::new()
  let src = fake_src()
  let mut total = 0
  let mut last : @protocol.AutoStepResult? = None
  for i = 0; i < 4; i = i + 1 {
    guard e.run_batch(vm, src, 4) is Ok(r) else { fail("批 \{i} 不应 Err") }
    total = total + r.payloads.length()
    last = Some(r)
    if r.finished {
      break
    }
  }
  guard last is Some(fin) else { fail("必有一次结果") }
  // 10 条指令 → 10 个 Ok 帧 + 1 个 Finished 帧（ip==len 的下一步）
  assert_eq(total, 11)
  assert_true(fin.finished)
  assert_false(fin.trapped)
  assert_true(e.is_finished)
  // 帧已入窗 + step_index 连续（0..10）
  assert_eq(e.frames.length(), 11)
  for k = 0; k < 11; k = k + 1 {
    guard e.frames.frame_at(k) is Some(p) else { fail("帧 \{k} 必在窗口") }
    assert_eq(p.step_index, k)
  }
}

///|
/// 锚 B：is_finished 粘性（坑 ⑥-6）——终结后再 run_batch 空帧不发。
test "engine_run_batch_finished_sticky" {
  let vm = @vm.VitroVM::new()
  vm.load_program(nop_program(2))
  let e = UnifiedEngine::new()
  let src = fake_src()
  ignore(e.run_batch(vm, src, 10))
  assert_true(e.is_finished)
  guard e.run_batch(vm, src, 10) is Ok(r) else { fail("粘性分支应 Ok") }
  assert_eq(r.payloads.length(), 0)
  assert_true(r.finished)
}

///|
/// 锚 C：max_steps 预算（U2#7 早退不丢帧）——Err 前已执行帧先入窗。
test "engine_run_batch_max_steps_budget" {
  let vm = @vm.VitroVM::new()
  vm.load_program(nop_program(10))
  let e = UnifiedEngine::with_max_steps(3)
  let src = fake_src()
  guard e.run_batch(vm, src, 10) is Err(msg) else { fail("超预算应 Err") }
  assert_true(msg.contains("执行步数超过限制"))
  // step=0,1,2,3 执行（4 帧）→ step 3 >= 3 触发（执行后检查——Rust
  // engine.rs:219 同位），帧先入窗再报错
  assert_eq(e.frames.length(), 4)
}

///|
/// 锚 D（⑤-5.1 专项）：Trap 回退改检查点+正向重放——trap 帧 = trap 前
/// 状态（step_index = trap 步号 / VM 回退到执行前 / 值栈恢复）。
test "engine_run_batch_trap_rollback_replay" {
  let vm = @vm.VitroVM::new()
  // PushConst 0 ×2（行 1/2）+ Div（行 3）——0/0 除零 trap
  vm.load_program(
    code_of([
      instr_at(@opcode.PushConst, 0, 1),
      instr_at(@opcode.PushConst, 0, 2),
      instr_at(@opcode.Div, 0, 3),
      instr_at(@opcode.Nop, 0, 3),
    ]),
  )
  let e = UnifiedEngine::new()
  let src = fake_src()
  guard e.run_batch(vm, src, 10) is Ok(r) else { fail("trap 走 Ok 通道") }
  assert_true(r.trapped)
  assert_false(r.finished)
  guard r.trap_message is Some(msg) else { fail("trap 文案必在") }
  assert_true(msg.length() > 0)
  // trap 帧：step_index = 2（Div 是第 3 步、执行前 executed=2），
  // code_line = 3（Div 的行号——回退态 = Div 执行前，current_line 已是
  // 上一条指令行？以 vm 实测为准：帧以 collect 采集为准）
  let n = r.payloads.length()
  assert_eq(r.payloads[n - 1].step_index, 2)
  // VM 回退态：executed 回到 2（trap 前一步完成态）、值栈两常量恢复
  assert_eq(vm.step_count, 2)
  assert_eq(vm.stack.length(), 2)
}

///|
/// 锚 E：窗口内 seek 直返——不动 VM（无重放），帧即缓存帧。
test "engine_seek_in_window_direct_return" {
  let vm = @vm.VitroVM::new()
  vm.load_program(nop_program(8))
  let e = UnifiedEngine::new()
  let src = fake_src()
  ignore(e.run_batch(vm, src, 8))
  let executed = vm.step_count
  let r = e.seek_to(3, vm, src)
  assert_true(r.success)
  guard r.payload is Some(p) else { fail("帧必在") }
  assert_eq(p.step_index, 3)
  // 直返分支不 restore——VM 状态原地
  assert_eq(vm.step_count, executed)
}

///|
/// 锚 F（越窗 seek 往返相等）：窗口滑走后 seek 回中段——重放重建帧与
/// 原帧关键字段一致；重放后 VM 在 target+1 态（续跑连续）。
test "engine_seek_beyond_window_replay_roundtrip" {
  let vm = @vm.VitroVM::new()
  vm.load_program(nop_program(8))
  let e = UnifiedEngine::new()
  let src = fake_src()
  ignore(e.run_batch(vm, src, 8))
  // 原帧关键性状（step_index → code_line 交错 1/2）
  guard e.frames.frame_at(1) is Some(orig) else { fail("原帧 1 必在") }
  // 帧 1 = Nop（StepEvent(1) 之后）→ code_line = 1
  assert_eq(orig.code_line, 1)
  // 模拟窗口滑走（reset_to 是越窗 seek 的强制前置同款通道）
  e.frames.reset_to(9)
  assert_true(e.frames.frame_at(1) is None)
  // 越窗 seek(1)：重放路径（检查点 0 ← run 首循环 should_checkpoint(0)）
  let r = e.seek_to(1, vm, src)
  assert_true(r.success)
  guard r.payload is Some(p) else { fail("seek 帧必在") }
  // 往返相等：step_index / code_line / heatmap_count 与原帧一致
  assert_eq(p.step_index, orig.step_index)
  assert_eq(p.code_line, orig.code_line)
  assert_eq(p.heatmap_count, orig.heatmap_count)
  // 重放终态：restore(cp=0) 后重放 0..=1 共 2 步 → executed = 2
  assert_eq(vm.step_count, 2)
  // 窗口重建后帧可再取
  assert_true(e.frames.frame_at(1) is Some(_))
}

///|
/// 锚 G（seek 后续跑连续）：锚 F 形态后续 run_batch——新帧 step_index
/// 从 vm.step_count 起连续推进到终结。
test "engine_seek_then_run_continuity" {
  let vm = @vm.VitroVM::new()
  vm.load_program(nop_program(8))
  let e = UnifiedEngine::new()
  let src = fake_src()
  ignore(e.run_batch(vm, src, 8))
  e.frames.reset_to(9)
  let r0 = e.seek_to(2, vm, src)
  assert_true(r0.success)
  assert_eq(vm.step_count, 3)
  // is_finished 已被 seek 复位（坑 ⑥-6 后半）
  assert_false(e.is_finished)
  guard e.run_batch(vm, src, 20) is Ok(r1) else { fail("续跑应 Ok") }
  assert_true(r1.finished)
  assert_eq(r1.payloads[0].step_index, 3)
  let last_idx = r1.payloads.length() - 1
  // 8 步程序终帧 = step_index 8（ip==len 的 Finished 步）
  assert_eq(r1.payloads[last_idx].step_index, 8)
}

///|
/// 锚 H：seek 超过程序末尾——重放遇 Finished 以该步为终点 success
/// （协议 §4.2 第 4 步）。
test "engine_seek_beyond_end_finished_path" {
  let vm = @vm.VitroVM::new()
  vm.load_program(nop_program(4))
  let e = UnifiedEngine::new()
  let src = fake_src()
  ignore(e.run_batch(vm, src, 4))
  e.frames.reset_to(99)
  let r = e.seek_to(100, vm, src)
  assert_true(r.success)
  guard r.payload is Some(p) else { fail("终帧必在") }
  // 4 指令 → 第 5 步（step_index=4）ip==len → Finished
  assert_eq(p.step_index, 4)
}

///|
/// 锚 I：无检查点 seek（未 run 过）——success=false + 文案。
test "engine_seek_no_checkpoint_fails" {
  let vm = @vm.VitroVM::new()
  vm.load_program(nop_program(4))
  let e = UnifiedEngine::new()
  let src = fake_src()
  let r = e.seek_to(2, vm, src)
  assert_false(r.success)
  guard r.error is Some(msg) else { fail("错误文案必在") }
  assert_true(msg.contains("没有可用的检查点"))
}

// ─────────────────────────────────────────────────────────────────────
// 小窗口引擎锚（2026-10-01 审阅 P1 补）：协议默认窗口 2_000 使 engine
// 层越窗路径不可锚（A12）——经 with_limits 缩窗后：批量 run（batch>1）
// 的窗口推进 + 双向越窗 seek 的重放收尾（finish_replay 分支在引擎语境
// 真触发）。
// ─────────────────────────────────────────────────────────────────────

///|
/// 锚 J：小窗口批量推进 + 后向越窗 seek——run_batch(30) 一批推 30 帧
/// （窗口 8 恒有界，起点随逐帧 trim 推进——U2#1 形态），seek(2) 越窗
/// 走重放（重放 3 帧 + finish_replay 截尾段）。
test "engine_small_window_batch_and_backseek" {
  let vm = @vm.VitroVM::new()
  vm.load_program(nop_program(40))
  let e = UnifiedEngine::with_limits(100_000, 8, 0.5)
  let src = fake_src()
  guard e.run_batch(vm, src, 30) is Ok(r) else { fail("批跑应 Ok") }
  assert_false(r.finished)
  // 窗口有界（push 自 trim）：len ≤ 8 且起点已推进
  assert_true(e.frames.length() <= 8)
  assert_true(e.frames.start_step() > 0, msg="30 帧后窗口起点须推进")
  // 后向越窗 seek(2)：nearest(2)=检查点 0（首循环 save(0)）→ 重放
  // 0..=2 → finish_replay(2)（want_start 钳 0 不 discard；expected=3）
  let sk = e.seek_to(2, vm, src)
  assert_true(sk.success)
  guard sk.payload is Some(p) else { fail("帧必在") }
  assert_eq(p.step_index, 2)
  assert_eq(e.frames.start_step(), 0)
  assert_eq(e.frames.length(), 3)
}

///|
/// 锚 K：前向越窗 seek——窗口滑过 cp 后 seek 至未入窗步（重放中
/// push 自 trim + finish_replay 的 want_start 语义）。
test "engine_small_window_forward_seek" {
  let vm = @vm.VitroVM::new()
  vm.load_program(nop_program(40))
  let e = UnifiedEngine::with_limits(100_000, 8, 0.5)
  let src = fake_src()
  ignore(e.run_batch(vm, src, 30))
  // 前向越窗：seek(35)（窗口已裁掉 22 之前的帧，cp=20 在 nearest(35)）
  let sk = e.seek_to(35, vm, src)
  assert_true(sk.success)
  guard sk.payload is Some(p) else { fail("帧必在") }
  assert_eq(p.step_index, 35)
  // finish_replay(35)：want_start = 35-8+1 = 28；重放 20..=35 共 16 帧
  // 经逐帧 trim（0.5 比例）后窗口有界
  assert_true(e.frames.length() <= 8)
  assert_true(
    e.frames.start_step() >= 28 - 4,
    msg="起点按 trim 推进（含比例舍入）",
  )
  assert_true(e.frames.frame_at(35) is Some(_))
  // 续跑连续（重放终态 = executed 36）
  assert_eq(vm.step_count, 36)
}
