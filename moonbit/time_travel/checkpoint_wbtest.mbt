///| L9 time_travel·CheckpointManager **门 3 六锚**（S8 批一号一段自
/// `vm/vm_wbtest.mbt` 迁入，2026-09-30——wbtest 随类型迁移：断言与构造
/// 原样，仅 vm 类型加 `@vm.` 限定 + 指令流 helper 随行拷贝）。
/// 迁移零语义变更：锚名不变（红→绿链可溯）；判据字符串形态照搬。

///|
/// 指令流 helper（拷自 vm/vm_exec_wbtest.mbt——wbtest 文件不跨包共享）。
fn code_of(insts : Array[@opcode.Instruction]) -> Array[@opcode.Instruction] {
  insts
}

///|
fn instr(op : @opcode.OpCode, operand : Int) -> @opcode.Instruction {
  @opcode.Instruction::new(op, operand, @source.SourceLoc::new(1, 1))
}

///|
/// 门 3 锚一：全量快照往返（save→变更→nearest→restore 回到过去）。
test "checkpoint_full_roundtrip" {
  let vm = @vm.VitroVM::new()
  let cm = CheckpointManager::new(4)
  // 运行 10 步（Nop 流），每步问 should_checkpoint
  vm.load_program(
    code_of([
      instr(@opcode.Nop, 0),
      instr(@opcode.PushConst, 1),
      instr(@opcode.Nop, 0),
      instr(@opcode.Nop, 0), // step 4
      instr(@opcode.PushConst, 2),
      instr(@opcode.Nop, 0),
      instr(@opcode.Nop, 0),
      instr(@opcode.Nop, 0), // step 8
      instr(@opcode.PushConst, 3),
      instr(@opcode.Nop, 0),
    ]),
  )
  for k = 0; k < 10; k = k + 1 {
    ignore(vm.step())
    if cm.should_checkpoint(vm.step_count, "") {
      cm.save(vm.step_count, vm)
    }
  }
  // 保存了 step 4/8 两个全量（4%4==0、8%4==0）
  assert_eq(cm.length(), 2)
  // 后续变更
  ignore(vm.step())
  assert_eq(vm.stack.length(), 3)
  // seek 回 step 8
  guard cm.nearest(8) is Some((s8, snap8)) else {
    fail("nearest(8) 必须命中")
  }
  assert_eq(s8, 8)
  vm.restore(snap8)
  assert_eq(vm.stack.length(), 2) // 回到 step 8 时只有 2 个 PushConst
  assert_eq(vm.step_count, 8)
}

///|
/// 门 3 锚二：增量快照（脏页 Delta——两步间只写一页，Delta 只含该页）。
test "checkpoint_incremental_dirty_page" {
  let vm = @vm.VitroVM::new()
  let cm = CheckpointManager::new(2)
  vm.load_program(
    code_of([
      instr(@opcode.Nop, 0),
      instr(@opcode.Nop, 0),
      instr(@opcode.Nop, 0),
    ]),
  )
  // step 2 全量
  cm.save(2, vm)
  ignore(vm.step())
  ignore(vm.step())
  // 写 0x6000 一字节 → 脏页 6
  guard vm.memory.store_i8(vm.mem_map, 0x6000U, 0x42) is Ok(_) else {
    fail("写")
  }
  // step 4 增量（2%5≠0 → Delta）
  cm.save(4, vm)
  assert_eq(cm.checkpoints.length(), 2)
  guard cm.checkpoints[1].1.memory is @vm.Delta(_, _) else {
    fail("第二个必须是 Delta")
  }
  guard cm.checkpoints[1].1.memory is @vm.Delta(base, ps) else {
    fail("重绑")
  }
  assert_eq(base, 2)
  assert_eq(ps.length(), 1) // 只脏了页 6
  assert_eq(ps[0].0, 6)
  // 再写 0x5000（页 5）→ step 6 增量含两页
  guard vm.memory.store_i8(vm.mem_map, 0x5000U, 0x55) is Ok(_) else {
    fail("写2")
  }
  cm.save(6, vm)
  guard cm.checkpoints[2].1.memory is @vm.Delta(_, ps2) else { fail("Delta") }
  assert_eq(ps2.length(), 2) // 页 5+6（脏页累积——不清位图直到全量）
  // seek 回 6（Delta 链重建）
  guard cm.nearest(6) is Some((s6, snap6)) else { fail("nearest(6)") }
  assert_eq(s6, 6)
  vm.restore(snap6)
  assert_eq(vm.memory.load_i8(vm.mem_map, 0x6000U), Ok(0x42))
  assert_eq(vm.memory.load_i8(vm.mem_map, 0x5000U), Ok(0x55))
  // seek 回 4（中间点）
  guard cm.nearest(4) is Some((_, snap4)) else { fail("nearest(4)") }
  vm.restore(snap4)
  assert_eq(vm.memory.load_i8(vm.mem_map, 0x6000U), Ok(0x42))
  assert_eq(vm.memory.load_i8(vm.mem_map, 0x5000U), Ok(0)) // 0x5000 还没写
}

///|
/// 门 3 锚三：淘汰不变量（step-0 锚点永不裁）。
test "checkpoint_eviction_invariants" {
  let vm = @vm.VitroVM::new()
  let cm = CheckpointManager::new(1)
  cm.set_max_checkpoints(5)
  // 模拟序列：0(F)/1(F)/2(F)/3(F)/4(F)/5(F)... 6 个后淘汰
  for st = 0; st < 8; st = st + 1 {
    // 原 vm.step_count = st 已删：跨包字段只读（MoonBit 实证），且 save 的
    // step 走显式参数——赋值仅影响快照内 step_count 元数据，本锚零断言
    cm.save(st, vm)
  }
  // 超限 8 > 5 → 淘汰 3 个
  assert_eq(cm.length(), 5)
  // step-0 锚点必须在（pinned）
  assert_eq(cm.checkpoints[0].0, 0)
  assert_true(cm.checkpoints[0].1.memory is @vm.Full(_))
  // 链头是 Full
  assert_true(cm.checkpoints[0].1.memory is @vm.Full(_))
}

///|
/// 门 3 锚三补（六轮审阅 P2-1）：**删 Full 级联的 pinned 场景**——锚三
/// 原构造是全 Full 链（full_every 节律被「len%5==0 且首个 is_empty」打
/// 满），对 `removed_is_full` 分支零覆盖：突变注入 `&& false`（还原
/// U2#5 缺陷版）原套 77/0 全绿。本锚构造 [0F,1D,2D,3D,4D,5F,6D,7D]
/// 后收紧上限触发淘汰——删 5(F) 时 remove_idx=1（pinned 锚点后），
/// 「删链头 Delta」防御分支只适用 remove_idx==0，唯一出口是级联
/// drain：6D/7D/8D 悬空（base=5 已删）必须清掉，否则 nearest 给出的
/// Delta 无法重建 = seek 静默错内存（U2#5 最坏调试器形状）。
test "checkpoint_evict_full_cascade_pinned" {
  let vm = @vm.VitroVM::new()
  let cm = CheckpointManager::new(1)
  cm.set_max_checkpoints(10)
  for st = 0; st <= 7; st = st + 1 {
    // 同锚三：跨包只读，赋值等价删除（快照内 step_count 元数据，零断言）
    cm.save(st, vm)
  }
  // full_every=5 节律：len0→F、len5→F，其余 D
  assert_eq(cm.length(), 8)
  assert_true(cm.checkpoints[5].1.memory is @vm.Full(_))
  assert_true(cm.checkpoints[6].1.memory is @vm.Delta(_, _))
  // 收紧上限 + 再 save 触发淘汰
  cm.set_max_checkpoints(4)
  // vm.step_count = 8 已删（同上，等价删除）
  cm.save(8, vm)
  // 四轮删 Delta（1D..4D）→ 删 5(F) → 级联 drain 6D/7D/8D → 终态 [0(F)]
  assert_eq(cm.length(), 1)
  assert_eq(cm.checkpoints[0].0, 0)
  assert_true(cm.checkpoints[0].1.memory is @vm.Full(_))
  // 淘汰后 seek 只能回 step-0 锚点（悬空 Delta 已清）
  guard cm.nearest(7) is Some((s, _)) else { fail("nearest(7) 必须命中 0") }
  assert_eq(s, 0)
}

///|
/// 门 3 锚四：should_checkpoint 智能模式（语义标签触发 + min_gap）。
test "checkpoint_smart_mode" {
  let cm = CheckpointManager::new(20)
  // 固定间隔
  assert_true(cm.should_checkpoint(20, ""))
  assert_true(cm.should_checkpoint(40, ""))
  assert_false(cm.should_checkpoint(21, ""))
  // 智能触发（控制流边界）
  assert_true(cm.should_checkpoint(5, "调用 qsort"))
  assert_true(cm.should_checkpoint(7, "返回"))
  assert_true(cm.should_checkpoint(9, "内存分配"))
  assert_true(cm.should_checkpoint(11, "释放内存"))
  assert_true(cm.should_checkpoint(13, "包含交换的循环"))
  assert_true(cm.should_checkpoint(15, "循环体"))
  // 非显著
  assert_false(cm.should_checkpoint(17, ""))
  assert_false(cm.should_checkpoint(18, "算术"))
  // 关 smart 后只剩固定间隔
  cm.set_smart_mode(false)
  assert_false(cm.should_checkpoint(5, "调用 qsort"))
  assert_true(cm.should_checkpoint(20, ""))
}

///|
/// 门 3 锚五：隔离区三件套随快照往返（quarantine/bytes/budget）。
test "checkpoint_quarantine_triple_roundtrip" {
  let vm = @vm.VitroVM::new()
  let cm = CheckpointManager::new(2)
  // 分配→登记→释放→隔离区活（allocate_raw 不登记 region——host_malloc
  // 才组合两步；此处用 register_alloc 模拟 host 层组合）
  let addr = vm.mem_map.allocate_raw(64U, @bytecode.MEM_SIZE)
  guard addr is Some(a) else { fail("分配必须成功") }
  vm.mem_map.register_alloc(a, 64, 1, "test", true)
  ignore(vm.mem_map.release(a, 64, 1))
  assert_true(vm.mem_map.quarantine_len() > 0)
  let q_before = vm.mem_map.quarantine_len()
  let qb_before = vm.mem_map.quarantine_bytes()
  let budget_before = vm.mem_map.quarantine_budget()
  cm.save(1, vm)
  // 后续变更：缩预算再分配触发驱逐（evict 条件是隔离字节超预算——
  // 非单次分配大小；缩到 32B 后 64B 块即超限驱逐）
  vm.mem_map.set_quarantine_budget(32)
  ignore(vm.mem_map.allocate_raw(16U, @bytecode.MEM_SIZE))
  assert_true(vm.mem_map.quarantine_len() < q_before)
  // seek 回 → 三件套恢复
  guard cm.nearest(1) is Some((_, snap)) else { fail("nearest") }
  vm.restore(snap)
  assert_eq(vm.mem_map.quarantine_len(), q_before)
  assert_eq(vm.mem_map.quarantine_bytes(), qb_before)
  assert_eq(vm.mem_map.quarantine_budget(), budget_before)
  // UAF 不出假阴性：回退后访问已释放块必命中 freed_logs
  assert_true(vm.mem_map.freed_logs_contains(a))
}
