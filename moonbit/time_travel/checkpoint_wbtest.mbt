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
fn instr(op : @opcode.OpCode, operand : Int32) -> @opcode.Instruction {
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
/// 门 3 锚三：淘汰不变量（step-0 锚点永不裁）。**#87 几何化淘汰改写**
/// （2026-10-27）：淘汰从 FIFO 改「贪心最小左间隙（平手取最老）」——
/// 0..7 连续等距保存（淘汰中途 len 回到 5 ⇒ save(6)/(7) 按 len%5 节律
/// 落 Full）终态从 [0F,4D,5F,6F,7F] 变为 [0F,2D,4D,6F,7F]：第二轮起
/// 最小间隙挪到 i2（隔一稀释）；第三轮删 5F 时后邻 6F 相邻——级联零
/// drain（真实 drain 场景由锚四补 20D/40D/60D 构造覆盖）。
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
  // 超限淘汰至 5：终态 [0F,2D,4D,6F,7F]
  assert_eq(cm.length(), 5)
  // step-0 锚点必须在（pinned）
  assert_eq(cm.checkpoints[0].0, 0)
  assert_true(cm.checkpoints[0].1.memory is @vm.Full(_))
  // 幸存 Delta 的 base 仍落场内 Full
  for pair in cm.checkpoints {
    match pair.1.memory {
      @vm.Full(_) => ()
      @vm.Delta(base, _) => assert_eq(base, 0)
    }
  }
}

///|
/// 门 3 锚三补（六轮审阅 P2-1；**#87 几何化淘汰改写构造**，2026-10-27）：
/// **删 Full 级联 drain 的 pinned 场景**。FIFO 时代的旧构造（0..7 等距 +
/// 收紧到 4）在新策略下由锚三覆盖；本锚改用「连续密区 + 跳步」构造，让
/// 5F 的左间隙在密区稀释完后成为全场最小——删 5(F) 时其后 20D/40D/60D
/// 悬空（base=5 已删）必须级联清掉，否则 nearest 给出的 Delta 无法重建
/// = seek 静默错内存（U2#5 最坏调试器形状）。终态 [0F,2D,4D] 为模拟器
/// 锁定真值（full:1 / delta:2 / drained:3）。
test "checkpoint_evict_full_cascade_pinned" {
  let vm = @vm.VitroVM::new()
  let cm = CheckpointManager::new(1)
  cm.set_max_checkpoints(10)
  // 构造 [0F,1D,2D,3D,4D,5F,20D,40D]（full_every=5 节律：len0/len5 → Full）
  for st in [0, 1, 2, 3, 4, 5, 20, 40] {
    // 同锚三：跨包只读，赋值等价删除（快照内 step_count 元数据，零断言）
    cm.save(st, vm)
  }
  assert_eq(cm.length(), 8)
  assert_true(cm.checkpoints[5].1.memory is @vm.Full(_))
  assert_true(cm.checkpoints[6].1.memory is @vm.Delta(_, _))
  // 收紧上限 + 再 save(60) 触发：删 1D（间隙 1）→ 删 3D（间隙 1）→
  // 5F 左间隙 1 成最小 → 删 Full 级联 drain 20D/40D/60D
  cm.set_max_checkpoints(3)
  cm.save(60, vm)
  // 终态 [0F,2D,4D]：悬空 Delta（base=5 已删）必须已被级联清除
  assert_eq(cm.length(), 3)
  assert_eq(cm.checkpoints[0].0, 0)
  assert_true(cm.checkpoints[0].1.memory is @vm.Full(_))
  for pair in cm.checkpoints {
    match pair.1.memory {
      @vm.Full(_) => ()
      @vm.Delta(base, _) => assert_eq(base, 0)
    }
  }
  // 淘汰后 seek 只能落 step-0 锚点前的幸存检查点（悬空 Delta 已清，
  // nearest(60) 命中 4 且可重建——base=0 在场）
  guard cm.nearest(60) is Some((s, _)) else { fail("nearest(60) 必须命中") }
  assert_eq(s, 4)
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

///|
/// #87 锚六：淘汰策略几何化——均匀保存下中段锚点不空洞。**红锚**（旧
/// FIFO 形态）：FIFO 保 {step-0} ∪ 最近 49 个 ⇒ 中段 [1500,2500) 零锚点
/// ⇒ nearest(中段) 落 step-0 全程重放——issue #87 的 seek(1M)=13.8s
/// 病灶（78M 步程序 500×）。几何化淘汰（最小左间隙合并）下近似等距
/// 分布：期望值来自 node 模拟器（worst=140 @t=1140；界取 3×N/K=246）。
test "checkpoint_eviction_geometric_coverage" {
  let vm = @vm.VitroVM::new()
  let cm = CheckpointManager::new(20)
  // 0..4000 每 20 步一存（201 笔，固定间隔形态——smart 判据不参与）
  for st = 0; st <= 4000; st = st + 20 {
    cm.save(st, vm)
  }
  assert_eq(cm.length(), 50)
  // step-0 锚点 pinned + 链头 Full
  assert_eq(cm.checkpoints[0].0, 0)
  assert_true(cm.checkpoints[0].1.memory is @vm.Full(_))
  // 中段覆盖：[1500,2500) 至少一个锚点（旧 FIFO = 空 ⇒ 本锚红）
  let mut mid = 0
  for pair in cm.checkpoints {
    if pair.0 >= 1500 && pair.0 < 2500 {
      mid = mid + 1
    }
  }
  assert_true(
    mid > 0,
    msg="中段 [1500,2500) 无锚点——淘汰策略中段空洞（#87 FIFO 形态）",
  )
  // 最大重放距离界：≤ 3×N/K（4000/49≈82 → 246；模拟实测 140）
  let mut worst = 0
  for t = 0; t <= 4000; t = t + 20 {
    guard cm.nearest(t) is Some((s, _)) else {
      fail("nearest(\{t}) 必须命中")
    }
    if t - s > worst {
      worst = t - s
    }
  }
  assert_true(
    worst <= 246,
    msg="最大重放距离 \{worst} 超 3×N/K 界 246（几何化失效）",
  )
}

///|
/// #87 锚七：几何化淘汰下 Full/Delta 链结构不变量——混合密度形态（固定
/// 间隔 + 近距智能边界）长跑后：递增序 / 链头 Full / 每 Delta 的 base
/// 锚仍在场内（悬空 Delta = seek 静默错内存，U2#5——几何化重写淘汰后
/// 的结构回归锚）。
test "checkpoint_eviction_chain_invariants_geometric" {
  let vm = @vm.VitroVM::new()
  let cm = CheckpointManager::new(7)
  cm.set_max_checkpoints(12)
  let mut k = 0
  for st = 0; st <= 2100; st = st + 7 {
    cm.save(st, vm)
    k = k + 1
    if k % 5 == 0 && st > 0 && st < 2000 {
      cm.save(st + 2, vm)
    }
  }
  assert_true(cm.length() <= 12)
  // 递增序
  for i = 1; i < cm.checkpoints.length(); i = i + 1 {
    assert_true(cm.checkpoints[i].0 > cm.checkpoints[i - 1].0)
  }
  // 链头 Full + step 最小
  assert_true(cm.checkpoints[0].1.memory is @vm.Full(_))
  // 每 Delta 的 base 必须命中场内某 Full 的 step（U2#5）
  for pair in cm.checkpoints {
    match pair.1.memory {
      @vm.Full(_) => ()
      @vm.Delta(base, _) => {
        let mut hit = false
        for q in cm.checkpoints {
          if q.0 == base && q.1.memory is @vm.Full(_) {
            hit = true
            break
          }
        }
        assert_true(
          hit,
          msg="Delta(base=\{base}) 悬空——base 锚已被淘汰（U2#5）",
        )
      }
    }
  }
}
