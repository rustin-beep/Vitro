///|
/// 快照往返锚（批一号核心义务——门 3 的模块级前置）：构造含全部字段族的
/// 活状态 → snapshot → churn → restore → 逐字段断言回到快照时点。
test "snapshot_restore_roundtrip_all_state" {
  let vm = VitroVM::new()
  // 制造活状态：值栈 / 调用帧（含宿主回调哨兵 None）/ 堆区域 + 释放 /
  // 教学观测 / 宿主域 / C# 三状态
  vm.stack.push(0xDEADBEEFUL)
  vm.stack.push(42UL)
  vm.call_stack.push(CallFrame::{
    return_ip: None,
    locals_base: 0x100U,
    local_count: 3,
    func_name: "cmp",
    original_stack_top: 1U,
    caller_line: 7,
    local_buffers: [
      @bytecode.LocalBuffer::{ offset: 4, size: 16, name: "buf", },
    ],
  })
  let p = vm.mem_map.allocate_raw(32U, @bytecode.MEM_SIZE)
  assert_true(p is Some(_))
  vm.step_count = 99
  vm.current_line = 12
  vm.error = "占位错误"
  vm.finished = false
  vm.exit_code = 0
  vm.qsort_depth = 2
  vm.argc = 1
  vm.argv_addr = 0xFF00U
  vm.vis_event_queue.push(VisEventData::{
    ty: 1,
    line: 3,
    extra0: 0,
    extra1: 0,
    extra2: 0,
    context: "compare",
  })
  vm.breakpoints.add(5)
  vm.breakpoints.add(2)
  vm.heatmap.set(3, 17UL)
  vm.snapshot_vars.set("i", 4UL)
  vm.last_snapshot_step = 40
  vm.waiting_input = true
  // 宿主域：输出与输入有内容
  @host.host_putchar(vm.output, 65UL)
  vm.exec_mode = Unwinding
  vm.exception_ref = Some(0x5000U)
  vm.unwind_remaining_frames = 3
  vm.unwind_target = Some(HandlerFrame::{
    catch_ip: 77,
    frame_idx: 1,
    stack_depth: 2,
    mem_stack_top: 0xF000U,
  })
  vm.handler_stack.push(HandlerFrame::{
    catch_ip: 77,
    frame_idx: 1,
    stack_depth: 2,
    mem_stack_top: 0xF000U,
  })
  let snap = vm.snapshot()
  // churn：一切照旧再改
  vm.stack.clear()
  vm.call_stack.clear()
  vm.step_count = 1000
  vm.error = ""
  vm.heatmap.set(3, 999UL)
  vm.breakpoints.clear()
  vm.exec_mode = Running
  vm.exception_ref = None
  vm.unwind_target = None
  vm.handler_stack.clear()
  vm.waiting_input = false
  ignore(vm.mem_map.release(0x5000U, 8, 1)) // 任意释放改堆状态
  // 恢复
  vm.restore(snap)
  assert_eq(vm.stack.length(), 2)
  assert_eq(vm.stack[0], 0xDEADBEEFUL)
  assert_eq(vm.call_stack.length(), 1)
  assert_true(vm.call_stack[0].return_ip is None)
  assert_eq(vm.call_stack[0].local_buffers.length(), 1)
  // 五字段全量断言（五轮审阅自更正补齐：b5ae8b2 改了 original_stack_top
  // 类型 Int→UInt 但该面当时无锚——仅读码判「已有测试覆盖」过于乐观）
  assert_eq(vm.call_stack[0].locals_base, 0x100U)
  assert_eq(vm.call_stack[0].local_count, 3)
  assert_eq(vm.call_stack[0].func_name, "cmp")
  assert_eq(vm.call_stack[0].original_stack_top, 1U)
  assert_eq(vm.call_stack[0].caller_line, 7)
  assert_eq(vm.step_count, 99)
  assert_eq(vm.current_line, 12)
  assert_eq(vm.error, "占位错误")
  assert_eq(vm.qsort_depth, 2)
  assert_eq(vm.argc, 1)
  assert_eq(vm.argv_addr, 0xFF00U)
  assert_eq(vm.vis_event_queue.length(), 1)
  assert_eq(vm.vis_event_queue[0].context, "compare")
  assert_eq(vm.heatmap.get(3), Some(17UL))
  assert_eq(vm.snapshot_vars.get("i"), Some(4UL))
  assert_eq(vm.last_snapshot_step, 40)
  assert_true(vm.waiting_input)
  assert_true(vm.exec_mode is Unwinding)
  assert_eq(vm.exception_ref, Some(0x5000U))
  assert_eq(vm.unwind_remaining_frames, 3)
  assert_true(vm.unwind_target is Some(_))
  assert_eq(vm.handler_stack.length(), 1)
  assert_eq(vm.handler_stack[0].catch_ip, 77)
  // 断点重建（Set↔排序数组往返）
  assert_true(vm.breakpoints.contains(2))
  assert_true(vm.breakpoints.contains(5))
  // 输出通道往返（putchar 落 'A' 一字节）
  assert_eq(vm.output.total_bytes(), 1)
  // 1MB 载体逐字节等价（全零态抽样——堆区/全局区各一点；NULL 陷阱区
  // 与栈区顶之外不抽样：check_access 的区段语义与本锚无关）
  guard vm.memory.load_i8(vm.mem_map, 0x5000U) is Ok(0) else {
    fail("堆起点必须可读")
  }
  guard vm.memory.load_i8(vm.mem_map, 0xFFFFFU) is Ok(0) else {
    fail("末位必须可读")
  }
  // 堆元数据往返：regions 数与快照一致
  assert_eq(vm.mem_map.regions_len(), snap.mem.regions.length())
}

///|
/// 快照独立性锚：restore 之后继续改运行态，**快照对象不被污染**
/// （「拷贝即快照」纪律——restore 侧再拷一次的存在理由）。
test "snapshot_independent_of_running_state" {
  let vm = VitroVM::new()
  vm.stack.push(1UL)
  vm.step_count = 10
  let snap = vm.snapshot()
  vm.restore(snap)
  // 恢复后改运行态
  vm.stack.push(2UL)
  vm.step_count = 999
  @host.host_putchar(vm.output, 66UL)
  // 快照对象不动
  assert_eq(snap.stack.length(), 1)
  assert_eq(snap.stack[0], 1UL)
  assert_eq(snap.step_count, 10)
  assert_eq(snap.output.total_bytes(), 0)
  // 再从同一快照恢复，得到的还是快照时点
  vm.restore(snap)
  assert_eq(vm.stack.length(), 1)
  assert_eq(vm.step_count, 10)
  assert_eq(vm.output.total_bytes(), 0)
}

///|
/// reset 会话配置保留锚（「先设上限再运行」不变量——Rust
/// `session_config_test` 回归语义 + 隔离预算同区）。
test "reset_preserves_session_config" {
  let vm = VitroVM::new()
  vm.set_max_steps(2000)
  vm.set_call_depth_limit(50)
  vm.deterministic = false
  vm.mem_map.set_quarantine_budget(1024)
  vm.stack.push(1UL)
  vm.step_count = 500
  vm.error = "x"
  let p = vm.mem_map.allocate_raw(64U, @bytecode.MEM_SIZE)
  assert_true(p is Some(_))
  vm.reset()
  // 配置保留
  assert_eq(vm.max_steps, 2000)
  assert_eq(vm.call_depth_limit, 50)
  assert_false(vm.deterministic)
  assert_eq(vm.mem_map.quarantine_budget(), 1024)
  // 执行态清零
  assert_eq(vm.stack.length(), 0)
  assert_eq(vm.step_count, 0)
  assert_eq(vm.error, "")
  assert_eq(vm.mem_map.regions_len(), 0)
  assert_eq(vm.mem_stack_top, @bytecode.STACK_START)
  // C# 三状态复位
  assert_true(vm.exec_mode is Running)
  assert_true(vm.exception_ref is None)
  assert_eq(vm.handler_stack.length(), 0)
}

///|
/// 三执行状态默认锚 + UNWINDING 中间态可快照（CS 计划 §4.5——「展开
/// 中间态必须可快照/恢复，否则 seek 落在展开区间中间恢复出撕裂状态」）。
test "exec_state_defaults_and_unwinding_snapshot" {
  let vm = VitroVM::new()
  assert_true(vm.exec_mode is Running)
  assert_true(vm.exception_ref is None)
  assert_eq(vm.unwind_remaining_frames, 0)
  assert_true(vm.unwind_target is None)
  assert_eq(vm.handler_stack.length(), 0)
  // UNWINDING 中间态：异常寄存器 + 剩余帧数 + 目标 handler 三件齐全
  vm.exec_mode = Unwinding
  vm.exception_ref = Some(0x7000U)
  vm.unwind_remaining_frames = 2
  let target = HandlerFrame::{
    catch_ip: 33,
    frame_idx: 0,
    stack_depth: 1,
    mem_stack_top: 0xE000U,
  }
  vm.unwind_target = Some(target)
  vm.handler_stack.push(target)
  let snap = vm.snapshot()
  vm.exec_mode = Running
  vm.exception_ref = None
  vm.unwind_remaining_frames = 0
  vm.unwind_target = None
  vm.handler_stack.clear()
  vm.restore(snap)
  assert_true(vm.exec_mode is Unwinding)
  assert_eq(vm.exception_ref, Some(0x7000U))
  assert_eq(vm.unwind_remaining_frames, 2)
  guard vm.unwind_target is Some(t) else {
    fail("目标 handler 必须随快照往返")
  }
  assert_eq(t.catch_ip, 33)
  assert_eq(vm.handler_stack.length(), 1)
}

///|
/// register_function 上限锚（U2#13 照搬：超 MAX_FUNCTIONS 拒绝且表不扩）。
test "register_function_respects_max_functions" {
  let vm = VitroVM::new()
  let meta = @bytecode.FuncMeta::{
    ip: 0,
    arg_count: 0,
    param_count: 0,
    local_count: 0,
    param_sizes: [],
    return_type: @ast.Type::Void(false),
    is_variadic: false,
    local_buffers: [],
  }
  assert_true(vm.register_function(0, meta))
  assert_true(vm.register_function(100, meta))
  assert_true(vm.register_function(65_535, meta))
  assert_false(vm.register_function(65_536, meta))
  assert_false(vm.register_function(2_147_483_647, meta))
  assert_false(vm.register_function(-1, meta))
  assert_true(vm.register_function_name(5, "main"))
  assert_false(vm.register_function_name(-1, "x"))
  // 稀疏表：未注册槽为 None，注册槽取回等价
  assert_true(vm.func_table[5] is None)
  guard vm.func_table[100] is Some(m) else { fail("100 号必须可取回") }
  assert_eq(m.ip, 0)
}

///|
/// 装载期派生索引锚（坑 12 结构性消除的形态验证）：set_symbols 后
/// locals_by_func / global_syms 就位，无需运行期重建。
test "set_symbols_builds_derived_index" {
  let vm = VitroVM::new()
  let syms : Array[@bytecode.Symbol] = []
  for
    t in [
      ("i", 4U, true, "main"),
      ("buf", 16U, true, "main"),
      ("n", 8U, true, "helper"),
      ("g", 0x1000U, false, ""),
    ] {
    syms.push(@bytecode.Symbol::{
      name: t.0,
      addr: t.1,
      is_local: t.2,
      ty: @ast.Type::Void(false),
      scope_depth: 0,
      func_name: t.3,
      decl_line: 1,
    })
  }
  vm.set_symbols(syms)
  guard vm.locals_by_func.get("main") is Some(m) else {
    fail("main 索引必须在")
  }
  assert_eq(m.get(4), Some("i"))
  assert_eq(m.get(16), Some("buf"))
  guard vm.locals_by_func.get("helper") is Some(h) else {
    fail("helper 索引必须在")
  }
  assert_eq(h.get(8), Some("n"))
  assert_eq(vm.global_syms.get(0x1000), Some("g"))
  // 装载是单点重建（重复 set 覆盖旧表）
  vm.set_symbols([])
  assert_eq(vm.locals_by_func.length(), 0)
}

///|
/// setup_argv 布局锚（R1 ③：argv 自 GLOBAL_REGION_LIMIT 向下；指针数组 +
/// 字符串数据；与全局数据冲突置 error）。
test "setup_argv_layout_and_conflict" {
  let vm = VitroVM::new()
  vm.setup_argv(2, ["a", "bc"], 0x2000U)
  assert_eq(vm.argc, 2)
  assert_eq(vm.argv_addr, 0xFFF0U) // footprint = align4(2*4 + (1+1)+(2+1)) = align4(12) = 12 → 0x10000-0xC
  // 指针数组两槽指向字符串区
  guard vm.memory.load_u32(vm.mem_map, 0xFFF0U) is Ok(s0) else {
    fail("slot0 必须可读")
  }
  assert_eq(s0, 0xFFF8U) // 0xFFF0 + 2*4
  // 首串 "a\0"
  guard vm.memory.load_i8(vm.mem_map, 0xFFF8U) is Ok(b0) else {
    fail("str0 必须可读")
  }
  assert_eq(b0, 'a'.to_int())
  guard vm.memory.load_i8(vm.mem_map, 0xFFF9U) is Ok(b1) else {
    fail("NUL 必须可读")
  }
  assert_eq(b1, 0)
  // argc<=0 短路
  vm.setup_argv(0, ["x"], 0U)
  assert_eq(vm.argc, 0)
  assert_eq(vm.argv_addr, 0U)
  // 冲突：global_data_end 顶到 argv 区 → error 置位
  vm.error = ""
  vm.setup_argv(4, ["aaaa"], 0xFFF0U)
  assert_eq(
    vm.error,
    "setup_argv: 命令行参数与全局数据区冲突（全局数据过大），无法安放 argv",
  )
}

///|
/// write_cstring 锚：Latin-1 口径字节 + NUL 终止 + 越界静默跳过。
test "write_cstring_bytes_and_bounds" {
  let vm = VitroVM::new()
  vm.write_cstring(0x5000U, "hi")
  assert_eq(vm.memory.load_i8(vm.mem_map, 0x5001U), Ok('i'.to_int()))
  guard vm.memory.load_i8(vm.mem_map, 0x5002U) is Ok(nul) else {
    fail("NUL 必须落")
  }
  assert_eq(nul, 0)
  // 越界（NULL 陷阱区）静默跳过——不炸、不写 error（读 NULL 区本身
  // 被 check_access 拦——这正是 NULL 陷阱语义，反向断言之）
  vm.write_cstring(0U, "x")
  assert_eq(vm.error, "")
  assert_true(vm.memory.load_i8(vm.mem_map, 0U) is Err(NullDeref(_, _)))
  // 末尾边界：addr + len == MEM_SIZE 拒绝（为 NUL 留 1 字节的语义）
  vm.write_cstring(@bytecode.MEM_SIZE - 1U, "ab")
  guard vm.memory.load_i8(vm.mem_map, @bytecode.MEM_SIZE - 1U) is Ok(v2) else {
    fail("末位可读")
  }
  assert_eq(v2, 0) // 未写入（静默跳过）
}

///|
/// 批四号锚：libc 产物装载完整性（3485 指令 + 88 函数 + file_id=1）。
test "libc_artifact_load_complete" {
  let libc = load_libc_artifact()
  assert_eq(libc.code.length(), 3485)
  assert_eq(libc.funcs.length(), 88)
  // file_id 置 1（覆盖率排除——首条 Nop）
  assert_eq(libc.code[0].loc.file_id, 1)
  // 首函数（按固定索引序）= isdigit @ 1000（ctype 段首——真值亲验自 JSON）
  assert_eq(libc.funcs[0].0, "isdigit")
  assert_eq(libc.funcs[0].1, 1000)
  // globals_32 = [[0,1]] 一条
  assert_eq(libc.globals_32.length(), 1)
}

///|
/// 批四号锚：setup_from_output 全协议（以最小用户程序验证合并/注册/入口）。
/// 用户 main：PushConst 7; Ret——装载后 ip = libc_code_len(3485)。
test "setup_from_output_protocol" {
  let vm = VitroVM::new()
  let out = @bytecode.CompileOutput::{
    code: [
      @opcode.Instruction::new(PushConst, 7, @source.SourceLoc::new(1, 1)),
      @opcode.Instruction::new(Ret, 0, @source.SourceLoc::new(1, 1)),
    ],
    globals_init_32: [],
    globals_init_64: [],
    func_table: Map([]),
    func_index: Map([]),
    string_data: [],
    source_map: [],
    symbols: [],
    struct_defs: Map([]),
    union_defs: Map([]),
    f64_constants: [],
    i64_constants: [],
    global_data_end: 0U,
  }
  vm.setup_from_output(out, 0, [])
  // 合并后 code 长度 = 3485 + 2
  assert_eq(vm.code.length(), 3487)
  // 入口 ip = libc_code_len
  assert_eq(vm.ip, 3485)
  // 用户函数注册（本例无用户函数——libc 88 个全注册）
  // func_table 稀疏数组长度 = 最大索引+1；抽一个固定索引验证
  guard vm.func_table.get(1023) is Some(Some(m)) else {
    fail("1023 必须注册")
  }
  assert_true(m.ip > 0)
  // 运行：PushConst 7; Ret → 栈顶 7
  let r = vm.run()
  assert_eq(r, 7)
}

///|
/// 门 3 锚一：检查点全量往返（interval 检查点 → 变更 → seek 回 → 状态等）。
test "checkpoint_full_roundtrip" {
  let vm = VitroVM::new()
  let cm = CheckpointManager::new(4)
  // 运行 10 步（Nop 流），每步问 should_checkpoint
  vm.load_program(
    code_of([
      instr(Nop, 0),
      instr(PushConst, 1),
      instr(Nop, 0),
      instr(Nop, 0), // step 4
      instr(PushConst, 2),
      instr(Nop, 0),
      instr(Nop, 0),
      instr(Nop, 0), // step 8
      instr(PushConst, 3),
      instr(Nop, 0),
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
  let vm = VitroVM::new()
  let cm = CheckpointManager::new(2)
  vm.load_program(code_of([instr(Nop, 0), instr(Nop, 0), instr(Nop, 0)]))
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
  guard cm.checkpoints[1].1.memory is Delta(_, pages) else {
    fail("第二个必须是 Delta")
  }
  guard cm.checkpoints[1].1.memory is Delta(base, ps) else { fail("重绑") }
  assert_eq(base, 2)
  assert_eq(ps.length(), 1) // 只脏了页 6
  assert_eq(ps[0].0, 6)
  // 再写 0x5000（页 5）→ step 6 增量含两页
  guard vm.memory.store_i8(vm.mem_map, 0x5000U, 0x55) is Ok(_) else {
    fail("写2")
  }
  cm.save(6, vm)
  guard cm.checkpoints[2].1.memory is Delta(_, ps2) else { fail("Delta") }
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
  let vm = VitroVM::new()
  let cm = CheckpointManager::new(1)
  cm.set_max_checkpoints(5)
  // 模拟序列：0(F)/1(F)/2(F)/3(F)/4(F)/5(F)... 6 个后淘汰
  for st = 0; st < 8; st = st + 1 {
    vm.step_count = st
    cm.save(st, vm)
  }
  // 超限 8 > 5 → 淘汰 3 个
  assert_eq(cm.length(), 5)
  // step-0 锚点必须在（pinned）
  assert_eq(cm.checkpoints[0].0, 0)
  assert_true(cm.checkpoints[0].1.memory is Full(_))
  // 链头是 Full
  assert_true(cm.checkpoints[0].1.memory is Full(_))
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
  let vm = VitroVM::new()
  let cm = CheckpointManager::new(1)
  cm.set_max_checkpoints(10)
  for st = 0; st <= 7; st = st + 1 {
    vm.step_count = st
    cm.save(st, vm)
  }
  // full_every=5 节律：len0→F、len5→F，其余 D
  assert_eq(cm.length(), 8)
  assert_true(cm.checkpoints[5].1.memory is Full(_))
  assert_true(cm.checkpoints[6].1.memory is Delta(_, _))
  // 收紧上限 + 再 save 触发淘汰
  cm.set_max_checkpoints(4)
  vm.step_count = 8
  cm.save(8, vm)
  // 四轮删 Delta（1D..4D）→ 删 5(F) → 级联 drain 6D/7D/8D → 终态 [0(F)]
  assert_eq(cm.length(), 1)
  assert_eq(cm.checkpoints[0].0, 0)
  assert_true(cm.checkpoints[0].1.memory is Full(_))
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
  let vm = VitroVM::new()
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
/// 门 3 集成版锚（2026-09-26 销账批）：libc 真装载（setup_from_output 合并
/// 3485 条）+ argv + vfs 预设 + 非平凡堆（两分配一释放——regions/quarantine/
/// freed_logs 三态非空）下的全量快照往返——恢复后 1MB 逐字节 + 堆元数据
/// 与快照时刻全等；快照后的一切变更（新分配/脏写/值栈）必须被回滚。
/// 对照模块级五锚（合成指令流），本锚以「cmd/run 同款集成链」销
/// 总计划 §2 门 3 的「S6 集成版验收」。
test "gate3_integrated_roundtrip_with_libc_setup" {
  let vm = VitroVM::new()
  let out = @bytecode.CompileOutput::{
    code: [
      @opcode.Instruction::new(PushConst, 7, @source.SourceLoc::new(1, 1)),
      @opcode.Instruction::new(Ret, 0, @source.SourceLoc::new(1, 1)),
    ],
    globals_init_32: [],
    globals_init_64: [],
    func_table: Map([]),
    func_index: Map([]),
    string_data: [],
    source_map: [],
    symbols: [],
    struct_defs: Map([]),
    union_defs: Map([]),
    f64_constants: [],
    i64_constants: [],
    global_data_end: 0U,
  }
  vm.setup_from_output(out, 1, ["prog"])
  ignore(vm.vfs.inject_preset_file(vm.mem_map, vm.memory, "t.txt", b"ab"))
  // 非平凡堆：两块分配 + 一块释放（隔离/日志非空）
  let p1 = vm.mem_map.allocate_raw(64U, @bytecode.MEM_SIZE).unwrap()
  vm.mem_map.register_alloc(p1, 64, 1, "a", true)
  let p2 = vm.mem_map.allocate_raw(48U, @bytecode.MEM_SIZE).unwrap()
  vm.mem_map.register_alloc(p2, 48, 2, "b", true)
  ignore(vm.mem_map.release(p1, 9, 100))
  guard vm.mem_map.verify() is Ok(_) else {
    fail("不变量自检必须通过")
  }
  // ── 快照时刻基线：1MB 映像 + 堆元数据指纹 ──
  let before = vm.dump_memory_raw()
  let regions_before = vm.mem_map.regions.length()
  let freed_before = vm.mem_map.freed_logs.length()
  // ── 快照后变更：新分配 + 脏写 + 值栈 ──
  let snap = vm.snapshot()
  let p3 = vm.mem_map.allocate_raw(32U, @bytecode.MEM_SIZE).unwrap()
  vm.mem_map.register_alloc(p3, 32, 3, "c", true)
  ignore(vm.memory.store_u64(vm.mem_map, p2, 0xDEADBEEFCAFEBABEUL))
  vm.stack.push(42UL)
  guard vm.mem_map.verify() is Ok(_) else {
    fail("不变量自检必须通过")
  }
  // ── 恢复：一切变更回滚 ──
  vm.restore(snap)
  // 1MB 逐字节
  let after = vm.dump_memory_raw()
  assert_eq(after.length(), 1024 * 1024, msg="映像恰 1MB")
  let mut mism = -1
  for i = 0; i < after.length(); i = i + 1 {
    if after[i] != before[i] {
      mism = i
      break
    }
  }
  assert_eq(mism, -1, msg="1MB 逐字节与快照时刻一致")
  assert_eq(vm.mem_map.regions.length(), regions_before, msg="区域数回滚")
  assert_eq(
    vm.mem_map.freed_logs.length(),
    freed_before,
    msg="freed 计数回滚",
  )
  assert_eq(vm.stack.length(), 0, msg="值栈回滚")
  guard vm.mem_map.verify() is Ok(_) else {
    fail("不变量自检必须通过")
  }
  // 恢复态仍可运行到程序语义终点（PushConst 7; Ret）
  assert_eq(vm.run(), 7, msg="恢复后可继续执行")
}
