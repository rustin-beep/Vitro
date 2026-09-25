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
