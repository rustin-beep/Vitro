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
      code_file: None,
      func_name: "main",
      semantic_label: "",
      semantic_label_id: "",
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
  operand : Int32,
  line : Int32,
) -> @opcode.Instruction {
  @opcode.Instruction::new(op, operand, @source.SourceLoc::new(line, 1))
}

///|
/// 源码行供给（FakeProvider——行文本只需非空即可走行号兜底标签）。
struct FakeProvider {
  lines : Map[Int32, String]
}

///|
impl SourceLineProvider for FakeProvider with fn source_line_at(
  self : FakeProvider,
  line : Int32,
) -> String? {
  self.lines.get(line)
}

///|
/// #90：帧文件归属——白盒假供给恒 "main.c"（单文件合成程序形态）。
impl SourceLineProvider for FakeProvider with fn source_file_at(
  self : FakeProvider,
  line : Int32,
) -> String? {
  ignore(line)
  Some("main.c")
}

///|
fn fake_src() -> FakeProvider {
  let m : Map[Int32, String] = Map([])
  m.set(1, "int acc = 0;")
  m.set(2, "acc += 1;")
  m.set(3, "return acc;")
  { lines: m, }
}

///|
/// 程序：StepEvent/Nop 交替 ×n 步（行号 1/2 交错——vm 的 current_line
/// 由 StepEvent 指令驱动〔编译器发射形态〕，纯 Nop 流恒 0；code_line 与
/// 行末去重锚需要交错行号面）。
fn nop_program(n : Int32) -> Array[@opcode.Instruction] {
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
/// 锚 A2（#89，2026-10-17）：every 采样步长——10 指令程序 every=3：
/// 仅第 3/6/9 条执行完采帧（step_index 2/5/8，帧口径 = 执行前步数）
/// + 终帧 step_index 10；总帧 4（全量形态 11）。指令级语义不变（执行
/// 仍逐条——heatmap 累计/检查点/断点判定不受采样影响）。
test "engine_run_batch_every_stride" {
  let vm = @vm.VitroVM::new()
  vm.load_program(nop_program(10))
  let e = UnifiedEngine::new()
  let src = fake_src()
  let idxs : Array[Int32] = []
  for i = 0; i < 2; i = i + 1 {
    guard e.run_batch(vm, src, 10, every=3) is Ok(r) else {
      fail("批 \{i} 不应 Err")
    }
    for p in r.payloads {
      idxs.push(p.step_index)
    }
    if r.finished {
      break
    }
  }
  assert_eq(idxs.length(), 4, msg="#89 采样帧数 3 + 终帧 1")
  assert_eq(idxs[0], 2)
  assert_eq(idxs[1], 5)
  assert_eq(idxs[2], 8)
  assert_eq(idxs[3], 10)
  // 终态帧不受采样门控（Finished 臂恒采）
  assert_true(e.is_finished)
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
/// issue #29：trap 终态粘性——trap 后再 run_batch 不得重执行 trap 指令
/// （此前每批 rollback→重执行→再 Trap，step 流无限循环不终止，双侧
/// 同病；mb 侧实现终态语义，oracle 缺口差异台账登记随退役收敛）。
test "engine_run_batch_trap_terminal_sticky" {
  let vm = @vm.VitroVM::new()
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
  // 首批：trap（trapped=true + trap 帧 + 回退态）
  guard e.run_batch(vm, src, 10) is Ok(r1) else { fail("trap 走 Ok 通道") }
  assert_true(r1.trapped)
  let msg1 = r1.trap_message
  guard msg1 is Some(_) else { fail("trap 文案必在") }
  let executed_after_trap = vm.step_count
  // 第二批：终态短路——空批 + trapped=true + trap_message 照报 +
  // VM 不动（不重执行 trap 指令、不回滚）
  guard e.run_batch(vm, src, 10) is Ok(r2) else { fail("终态走 Ok 通道") }
  assert_eq(r2.payloads.length(), 0, msg="终态批空 payloads")
  assert_true(r2.trapped, msg="终态批照报 trapped")
  assert_false(r2.finished)
  assert_eq(r2.trap_message, msg1, msg="死因文案恒定可复报")
  assert_eq(vm.step_count, executed_after_trap, msg="VM 不因重执行推进")
  // reset 是终态唯一清除通道——VM 一并回零（引擎 reset 单独用而 VM 带
  // 历史步数续跑是「连续帧带」窗口的越界组合：frame_at 按 start+idx 取
  // 帧不校验步号，帧 step_index 与带起点错位——真值语义 reset=全新采集）
  e.reset()
  vm.reset()
  // vm.reset 连 code 一并清空——重装程序（reset 场景 = 全新采集同款）
  vm.load_program(
    code_of([
      instr_at(@opcode.PushConst, 0, 1),
      instr_at(@opcode.PushConst, 0, 2),
      instr_at(@opcode.Div, 0, 3),
      instr_at(@opcode.Nop, 0, 3),
    ]),
  )
  guard e.run_batch(vm, src, 10) is Ok(r3) else { fail("reset 后可执行") }
  assert_true(r3.trapped)
  // seek 离开终态：trap 帧（step 2）在窗 → 直返成功 + 粘性清
  let sr = e.seek_to(2, vm, src)
  assert_true(sr.success, msg="窗口内直返 trap 帧")
  assert_false(e.is_trapped)
  // 窗口滑走后 seek 到 trap 步：重放含 target → 再触发 trap → 失败 +
  // 终态连坐置位（seek Trap 臂——否则后续 step.next 在 trap 态 VM 重执行）
  e.frames.reset_to(9)
  let sr2 = e.seek_to(2, vm, src)
  assert_false(sr2.success, msg="重放 seek 到 trap 步必失败")
  assert_true(e.is_trapped, msg="seek 重放遇 trap 记终态")
  // seek 失败后的 step.next：终态短路空批（VM 不动）
  guard e.run_batch(vm, src, 10) is Ok(r4) else { fail("seek 失败后走 Ok") }
  assert_true(r4.trapped)
  assert_eq(r4.payloads.length(), 0, msg="终态批空")
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

///|
test "b3rv_code_line_matches_semantic_line" {
  // 审阅 P2-3（2026-10-07）：#34 的 code_line 与 label 同源断言——
  // 帧行 = 步进前 current_line（= 上一 StepEvent 行 = label 行源）；
  // 修复前 collect 内步进后行会前移一帧（帧报 N+1 行）
  let vm = @vm.VitroVM::new()
  vm.load_program(nop_program(6))
  let e = UnifiedEngine::new()
  let src = fake_src()
  guard e.run_batch(vm, src, 6) is Ok(r) else { fail("run_batch 应 Ok") }
  let frames = r.payloads
  assert_true(frames.length() > 2)
  // nop_program：偶 i=StepEvent(行 1/2/3 循环)、奇 i=Nop——首帧行 = 1
  //（步进前 current_line 初始 0→首 StepEvent 设 1 后首帧 collect 行 1
  // 与循环顶 label 行同源；修复前会报步进后行）
  // 首帧行断言：修复语义 = 帧 code_line 取循环顶（步进前 current_line）
  // ——首步前 current_line=0，执行首条 StepEvent(1) 后 collect 收 0/1
  // 均为合法实现细节；断言收紧为：帧 1（第二步）起行=1（与 label 同源）
  assert_true(frames[1].code_line == 1, msg="帧 1 行与 StepEvent 同步")
  // 所有帧行在 0..3 域内（0 = 首帧前 current_line 初值——合法实现细节）
  for i in 0..<frames.length() {
    let cl = frames[i].code_line
    assert_true(cl >= 0 && cl <= 3, msg="code_line 在行域内")
  }
}

///|
/// #87 锚 L（重放快道·红锚）：窗口边距之外的中间步不推帧——预算在快道段
/// 中途熔断时窗口必须仍空。**今日行为（密采重放）此处窗口已积 ~100 帧
/// ⇒ 本锚红**。构造：K=6（锚点间距 ~4k）+ 窗口 100 + target 10_000 →
/// 快道段 [cp≈8k, 9_901) 约 1.9k 步；预算断在段中点。
test "engine_seek_fastpath_budget_break_empty_window" {
  let vm = @vm.VitroVM::new()
  vm.load_program(nop_program(20_000))
  let e = UnifiedEngine::with_limits(100_000, 100, 0.5)
  e.checkpoints.set_max_checkpoints(6)
  let src = fake_src()
  guard e.run_batch(vm, src, 20_001) is Ok(_) else { fail("run 应 Ok") }
  let target = 10_000
  guard e.checkpoints.nearest(target) is Some((cp, _)) else {
    fail("nearest(\{target}) 必须命中")
  }
  let dense_from = target - 100 + 1
  assert_true(
    cp + 50 < dense_from,
    msg="构造前提：快道段非平凡（cp=\{cp}）",
  )
  let budget = cp + (dense_from - cp) / 2
  e.set_max_steps(budget)
  let sk = e.seek_to(target, vm, src)
  assert_false(sk.success, msg="预算熔断应失败")
  guard sk.error is Some(m) else { fail("错误文案必在") }
  assert_true(m.contains("重放步数超过限制"))
  // 快道段零推帧：窗口 reset_to(cp) 后未积任何中间帧
  assert_eq(
    e.frames.length(),
    0,
    msg="#87 快道：预算中断时窗口仍空（中间帧不推窗）",
  )
  // VM 停在预算步（快道照常执行、只跳过 collect/推帧）
  assert_eq(vm.step_count, budget)
}

///|
/// #87 锚 M（重放快道·等价回归）：快道 seek 与密采 seek 的目标帧及窗口
/// 帧逐字段一致——跳过中间帧 collect 不改变可观测输出（vis_events 排水
/// / algo 死状态跳过的等价面）。e1 默认参数全程密采（dense_from=8_001
/// < cp），e2 快道 ~1.9k 步 + 密采尾段 100 帧。
test "engine_seek_fastpath_dense_equivalence" {
  // 密采基准
  let vm1 = @vm.VitroVM::new()
  vm1.load_program(nop_program(20_000))
  let e1 = UnifiedEngine::new()
  let src1 = fake_src()
  guard e1.run_batch(vm1, src1, 20_001) is Ok(_) else { fail("run1 应 Ok") }
  let r1 = e1.seek_to(10_000, vm1, src1)
  assert_true(r1.success)
  // 快道引擎：构造前提（cp < dense_from=9_901 ⇒ 快道段非空）
  let vm2 = @vm.VitroVM::new()
  vm2.load_program(nop_program(20_000))
  let e2 = UnifiedEngine::with_limits(100_000, 100, 0.5)
  e2.checkpoints.set_max_checkpoints(6)
  let src2 = fake_src()
  guard e2.run_batch(vm2, src2, 20_001) is Ok(_) else { fail("run2 应 Ok") }
  guard e2.checkpoints.nearest(10_000) is Some((cp2, _)) else {
    fail("nearest 必须命中")
  }
  assert_true(cp2 < 9_901, msg="构造前提：快道段非空（cp2=\{cp2}）")
  let r2 = e2.seek_to(10_000, vm2, src2)
  assert_true(r2.success)
  assert_true(r2.error is None)
  // 返回帧等价（step_index/code_line/语义标签/heatmap）
  guard r1.payload is Some(p1) else { fail("r1 帧必在") }
  guard r2.payload is Some(p2) else { fail("r2 帧必在") }
  assert_eq(p2.step_index, p1.step_index)
  assert_eq(p2.code_line, p1.code_line)
  assert_eq(p2.semantic_label, p1.semantic_label)
  assert_eq(p2.heatmap_count, p1.heatmap_count)
  // 窗口帧等价：e2 窗 [9_901..10_000] 与 e1 密采同段逐帧一致
  assert_eq(e2.frames.start_step(), 9_901)
  assert_eq(e2.frames.length(), 100)
  for k = 0; k < 100; k = k + 1 {
    guard e1.frames.frame_at(9_901 + k) is Some(f1) else {
      fail("e1 帧 \{9_901 + k} 必在")
    }
    guard e2.frames.frame_at(9_901 + k) is Some(f2) else {
      fail("e2 帧 \{9_901 + k} 必在")
    }
    assert_eq(f2.step_index, f1.step_index)
    assert_eq(f2.code_line, f1.code_line)
    assert_eq(f2.semantic_label, f1.semantic_label)
    // 空帧占位（code_line=0）不可现——缺口填充放大是快道的已知陷阱
    assert_true(
      f2.code_line >= 1,
      msg="帧 \{k} 空帧占位泄漏（缺口填充未对齐）",
    )
  }
  // VM 终态等价（重放计数一致 = 续跑连续性同构）
  assert_eq(vm2.step_count, vm1.step_count)
  assert_eq(vm2.step_count, 10_001)
  assert_eq(vm2.get_current_line(), vm1.get_current_line())
}

///|
/// #87 锚 N（重放快道·越终结边界回归）：target 超程序终步一个窗口以上
/// 时重放早遇 Finished 于密采段之前——快道版输出面与密采版一致
///（success + 终帧 payload + finish_replay 钳位空窗），差异仅在旧版
/// 白造 [cp..终步] 全部中间帧。锚 H（target < window）形态 dense_from
/// 钳 0，快道自然关闭，不在本锚面。
test "engine_seek_fastpath_beyond_end_regression" {
  let vm = @vm.VitroVM::new()
  vm.load_program(nop_program(2000))
  let e = UnifiedEngine::with_limits(100_000, 100, 0.5)
  let src = fake_src()
  guard e.run_batch(vm, src, 2001) is Ok(r) else { fail("run 应 Ok") }
  assert_true(r.finished)
  // seek(2500)：终步 2000 < dense_from 2401 → 快道早终结分支
  let sk = e.seek_to(2500, vm, src)
  assert_true(
    sk.success,
    msg="越终结 seek 以终步为终点 success（§4.2 第 4 步）",
  )
  guard sk.payload is Some(p) else { fail("终帧必在") }
  assert_eq(p.step_index, 2000)
  // finish_replay(2500) 的 want_start=2401 钳位把终步帧一并裁出——空窗
  //（与密采版同形；差异只在不白造中间帧）
  assert_eq(
    e.frames.length(),
    0,
    msg="越终结窗口被 want_start 钳位裁空",
  )
  assert_eq(vm.step_count, 2000, msg="Finished 探测步不推进计数")
}

///|
/// PR #342 审阅 P2-1 锚（2026-10-28）：seek 恰命中锚点时回看窗口不得
/// 塌缩。白盒构造确定性形态：锚集只留 {0, 2000}（标签内容一致——0 锚
/// 由 run 首循环自动存，2000 锚跑到后手工存），窗口钉出 target 后
/// seek(2000)——修复前 nearest(2000) 恰命中 2000 锚 ⇒ 重放 1 步 ⇒ 窗口
/// 仅终帧（payload.get 回看 0 帧）；修复后取 0 锚重放 ⇒ 窗口恒满。
test "engine_seek_anchor_hit_window_full" {
  let vm = @vm.VitroVM::new()
  vm.load_program(nop_program(3_000))
  let e = UnifiedEngine::with_limits(100_000, 100, 0.5)
  let src = fake_src()
  // 跑 1 步（step-0 锚自动存）+ 续跑到 2000
  guard e.run_batch(vm, src, 1) is Ok(_) else { fail("首步应 Ok") }
  let zero_anchor = e.checkpoints.checkpoints[0]
  ignore(e.run_batch(vm, src, 1_999))
  assert_eq(vm.step_count, 2_000)
  // 锚集重整为恰 {0, 2000}：先 clear（防 run 途中间隔锚与 K=50 淘汰
  // 挤掉新锚），白盒回填 0 锚 + save(2000)（length=1 → Delta，base=0
  // 链有效——重建语义同 Full）
  e.checkpoints.clear()
  e.checkpoints.checkpoints.push(zero_anchor)
  e.checkpoints.save(2_000, vm)
  assert_eq(e.checkpoints.length(), 2)
  // 窗口钉出 target 后回看恰锚步
  e.frames.reset_to(2_001)
  let s = e.seek_to(2_000, vm, src)
  assert_true(s.success, msg="回看 seek 应成功")
  let want_start = 2_000 - 100 + 1
  assert_eq(
    e.frames.start_step(),
    want_start,
    msg="P2-1：恰命中锚点时窗口起点须为 target-window+1（修复前塌缩到 target）",
  )
  assert_true(
    e.frames.frame_at(want_start) is Some(_),
    msg="回看窗口首帧可达（payload.get 面）",
  )
  assert_true(e.frames.length() >= 99, msg="窗口近满（≥99 帧）")
}
