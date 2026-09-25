///|
/// 黑盒面消费点名（对外面闸义务）：本包全部 pub 符号的 `@vm.` 消费形态。
test "vm_public_surface_smoke" {
  let vm = @vm.VitroVM::new()
  // 装载最小程序：PushConst 7; Ret
  vm.load_program([
    @opcode.Instruction::new(
      @opcode.OpCode::PushConst,
      7,
      @source.SourceLoc::new(1, 1),
    ),
    @opcode.Instruction::new(
      @opcode.OpCode::Ret,
      0,
      @source.SourceLoc::new(1, 1),
    ),
  ])
  vm.set_max_steps(100)
  vm.set_call_depth_limit(64)
  vm.set_deterministic(true)
  vm.set_vis_event_lines([(1, 1, "compare")])
  vm.set_globals_32([(0U, 42)])
  vm.set_globals_64([(8U, 0xAAAAUL)])
  vm.set_f64_constants([1.5])
  vm.set_i64_constants([7L])
  assert_true(
    vm.register_function(0, @bytecode.FuncMeta::{
      ip: 0,
      arg_count: 0,
      param_count: 0,
      local_count: 0,
      param_sizes: [],
      return_type: @ast.Type::Int(false, false),
      is_variadic: false,
      local_buffers: [],
    }),
  )
  assert_true(vm.register_function_name(0, "main"))
  vm.setup_argv(1, ["prog"], 0U)
  vm.write_cstring(0x5000U, "hi")
  // 快照往返（公开面）
  let snap = vm.snapshot()
  vm.reset()
  vm.restore(snap)
  // 常量锚
  assert_eq(@vm.MAX_FUNCTIONS, 65_536)
  assert_eq(@vm.MAX_STACK_DEPTH, 10_000)
  assert_eq(@vm.DEFAULT_MAX_STEPS, 10_000_000)
  assert_eq(@vm.VIS_EVENT_LIMIT, 1024)
  assert_eq(@vm.SNAPSHOT_INTERVAL, 100_000)
}

///|
/// 类型面消费点名：StepResult 五态 / ExecMode 两态 / MemoryImage 二分 /
/// 帧类型构造（宿主回调哨兵 = return_ip None）。
test "vm_type_surface" {
  let results : Array[@vm.StepResult] = [
    @vm.StepResult::Ok,
    @vm.StepResult::Paused,
    @vm.StepResult::Finished,
    @vm.StepResult::Trap,
    @vm.StepResult::WaitingInput,
  ]
  assert_eq(results.length(), 5)
  assert_true(@vm.ExecMode::Running != @vm.ExecMode::Unwinding)
  let full : @vm.MemoryImage = @vm.MemoryImage::Full(
    FixedArray::make(4, b'\x00'),
  )
  let delta : @vm.MemoryImage = @vm.MemoryImage::Delta(0, [
    (0, FixedArray::make(4, b'\x01')),
  ])
  assert_true(full != delta)
  let frame : @vm.CallFrame = @vm.CallFrame::{
    return_ip: None,
    locals_base: 0x100U,
    local_count: 1,
    func_name: "cmp",
    original_stack_top: 0,
    caller_line: 3,
    local_buffers: [],
  }
  assert_true(frame.return_ip is None)
  let handler : @vm.HandlerFrame = @vm.HandlerFrame::{
    catch_ip: 9,
    frame_idx: 0,
    stack_depth: 1,
    mem_stack_top: 0xF000U,
  }
  assert_eq(handler.catch_ip, 9)
  let vis : @vm.VisEventData = @vm.VisEventData::{
    ty: 1,
    line: 2,
    extra0: 3,
    extra1: 4,
    extra2: 5,
    context: "swap",
  }
  assert_eq(vis.context, "swap")
  let access : @vm.VariableAccess = @vm.VariableAccess::{
    name: "x",
    access_type: Read,
  }
  assert_true(access.access_type is @memory.AccessKind::Read)
}
