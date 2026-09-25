///|
/// executor 段一锚：栈 / 算术（溢出 trap 语义）/ run 返回值。
/// 直驱最小程序（批二号 wbtest 形态——对齐 Rust `executor/mod.rs:358-`
/// 的 set_test_code 直驱单测）。
fn code_of(insts : Array[@opcode.Instruction]) -> Array[@opcode.Instruction] {
  insts
}

///|
fn instr(op : @opcode.OpCode, operand : Int) -> @opcode.Instruction {
  @opcode.Instruction::new(op, operand, @source.SourceLoc::new(1, 1))
}

///|
test "exec_push_add_run_returns_last" {
  let vm = VitroVM::new()
  vm.load_program(
    code_of([instr(PushConst, 40), instr(PushConst, 2), instr(Add, 0)]),
  )
  let ret = vm.run()
  assert_eq(ret, 42)
  assert_true(vm.error.is_empty())
  assert_eq(vm.step_count, 3)
}

///|
/// 有符号加法溢出 → 教学 trap（i64 中转 + 范围检查；INT_MAX + 1）。
test "exec_add_overflow_traps" {
  let vm = VitroVM::new()
  vm.load_program(
    code_of([instr(PushConst, 2147483647), instr(PushConst, 1), instr(Add, 0)]),
  )
  let r = vm.step()
  let r2 = vm.step()
  assert_true(r is Ok)
  assert_true(r2 is Ok)
  let r3 = vm.step()
  assert_true(r3 is Trap)
  assert_eq(
    vm.error,
    "整数加法溢出。两个很大的正数（或很小的负数）相加超出了 int 能表示的范围。\n📍 发生在第 1 行 第 1 列",
  )
}

///|
/// U 族回绕：UAdd(2147483647, 1) = -2147483648 位模式（静默回绕不 trap）。
test "exec_uadd_wraps_silently" {
  let vm = VitroVM::new()
  vm.load_program(
    code_of([instr(PushConst, 2147483647), instr(PushConst, 1), instr(UAdd, 0)]),
  )
  ignore(vm.step())
  ignore(vm.step())
  let r = vm.step()
  assert_true(r is Ok)
  assert_eq(vm.stack[vm.stack.length() - 1].to_int(), -2147483648)
}

///|
/// 除零 → 教学 trap（format_div_zero_error 文案首段）。
test "exec_div_zero_traps_with_diag" {
  let vm = VitroVM::new()
  vm.load_program(
    code_of([instr(PushConst, 10), instr(PushConst, 0), instr(Div, 0)]),
  )
  ignore(vm.step())
  ignore(vm.step())
  let r = vm.step()
  assert_true(r is Trap)
  assert_true(vm.error.contains("😵 除零错误：你试图用 10 除以 0"))
}

///|
/// INT_MIN % -1 先拦截（坑 8：panic 击穿防御的 MoonBit 对应锚）。
test "exec_mod_min_minus_one_traps" {
  let vm = VitroVM::new()
  vm.load_program(
    code_of([instr(PushConst, -2147483648), instr(PushConst, -1), instr(Mod, 0)]),
  )
  ignore(vm.step())
  ignore(vm.step())
  let r = vm.step()
  assert_true(r is Trap)
  assert_true(vm.error.contains("整数取模溢出"))
}

///|
/// 局部变量往返 + last_accessed_vars 记录（派生索引取名）。
test "exec_local_store_load_roundtrip" {
  let vm = VitroVM::new()
  // 符号表：main 的局部 i @ offset 4
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
  // 当前帧：locals_base = 0x8000（手动 push，绕过 Call——控制流族段二接线）
  vm.call_stack.push(CallFrame::{
    return_ip: Some(0),
    locals_base: 0x8000U,
    local_count: 1,
    func_name: "main",
    original_stack_top: 0,
    caller_line: 0,
    local_buffers: [],
  })
  vm.load_program(
    code_of([instr(PushConst, 99), instr(StoreLocal, 4), instr(LoadLocal, 4)]),
  )
  let ret = vm.run()
  assert_eq(ret, 99)
  // last_accessed_vars：最后一步是 LoadLocal（Read）
  assert_eq(vm.last_accessed_vars.length(), 1)
  assert_eq(vm.last_accessed_vars[0].name, "i")
  assert_true(vm.last_accessed_vars[0].access_type is Read)
  // 内存落点：0x8004 = 99
  assert_eq(vm.memory.load_u32(vm.mem_map, 0x8004U), Ok(99U))
}

///|
/// 全局变量往返（GLOBAL_START + offset 编址）。
test "exec_global_store_load" {
  let vm = VitroVM::new()
  vm.load_program(
    code_of([instr(PushConst, 7), instr(StoreGlobal, 8), instr(LoadGlobal, 8)]),
  )
  let ret = vm.run()
  assert_eq(ret, 7)
  assert_eq(vm.memory.load_u32(vm.mem_map, @bytecode.GLOBAL_START + 8U), Ok(7U))
}

///|
/// StepEvent：断点暂停（Paused）+ vis 事件行命中 + 环形上限。
test "exec_step_event_breakpoint_and_vis" {
  let vm = VitroVM::new()
  vm.breakpoints.add(5)
  vm.set_vis_event_lines([(5, 2, "compare")])
  vm.load_program(code_of([instr(StepEvent, 3), instr(StepEvent, 5)]))
  let r1 = vm.step()
  assert_true(r1 is Ok)
  assert_eq(vm.current_line, 3)
  let r2 = vm.step()
  assert_true(r2 is Paused)
  assert_true(vm.paused)
  assert_eq(vm.current_line, 5)
  // vis 事件命中（行 5 带 ty=2/context）
  assert_eq(vm.vis_event_queue.length(), 1)
  assert_eq(vm.vis_event_queue[0].context, "compare")
  assert_eq(vm.vis_event_queue[0].ty, 2)
}

///|
/// vis 事件环形上限（1024 丢最旧）。
test "exec_vis_event_ring_limit" {
  let vm = VitroVM::new()
  vm.set_vis_event_lines([(1, 1, "ctx")])
  let code : Array[@opcode.Instruction] = []
  for i = 0; i < 1100; i = i + 1 {
    code.push(instr(StepEvent, 1))
  }
  vm.load_program(code)
  for i = 0; i < 1100; i = i + 1 {
    match vm.step() {
      Ok => ()
      _ => fail("无断点不应中断（第 \{i} 步）")
    }
  }
  assert_eq(vm.vis_event_queue.length(), 1024)
}

///|
/// TrapBounds（修正版）：越界 → Trap + 数组名诊断。
test "exec_trap_bounds_symbol_diag_v2" {
  let vm = VitroVM::new()
  vm.set_symbols([
    @bytecode.Symbol::{
      name: "a",
      addr: 4U,
      is_local: true,
      ty: @ast.Type::Array(@ast.Type::Int(false, false), 4, [], false, false, []),
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
    original_stack_top: 0,
    caller_line: 0,
    local_buffers: [],
  })
  vm.load_program(code_of([instr(PushConst, 4), instr(TrapBounds, 0)]))
  ignore(vm.step())
  let r = vm.step()
  assert_true(r is Trap)
  assert_true(
    vm.error.contains(
      "🚫 数组越界：你访问了 a[4]，但数组 'a' 只有 4 个元素",
    ),
  )
}

///|
/// max_steps 无限循环保险丝（步数超限 trap）。
test "exec_max_steps_fuse" {
  let vm = VitroVM::new()
  vm.set_max_steps(10)
  let code : Array[@opcode.Instruction] = []
  for i = 0; i < 20; i = i + 1 {
    code.push(instr(Nop, 0))
  }
  vm.load_program(code)
  let mut trapped = false
  for i = 0; i < 15; i = i + 1 {
    match vm.step() {
      Trap => {
        trapped = true
        break
      }
      Ok => ()
      _ => fail("不期待的其他结果（第 \{i} 步）")
    }
  }
  assert_true(trapped)
  assert_true(vm.error.contains("🔄 程序执行步数超过限制"))
}

///|
/// 栈下溢：Pop 空栈 → trap（首错文案）。
test "exec_stack_underflow_traps" {
  let vm = VitroVM::new()
  vm.load_program(code_of([instr(Pop, 0)]))
  let r = vm.step()
  assert_true(r is Trap)
  assert_eq(vm.error, "运行时错误：栈下溢")
}

///|
/// Memcpy/Memset 弹参序与结果（受检通道 + 指针压回）。
test "exec_memcpy_memset" {
  let vm = VitroVM::new()
  // Memset 压入序（栈顶 = 弹参序首）：size → value → ptr
  vm.load_program(
    code_of([
      instr(PushConst, 8),
      instr(PushConst, 0x42),
      instr(PushConst, 0x6000),
      instr(Memset, 0),
    ]),
  )
  let ret = vm.run()
  assert_eq(ret, 0x6000) // 指针压回（返回值=栈顶）
  // 8 字节全 0x42
  for k = 0; k < 8; k = k + 1 {
    assert_eq(
      vm.memory.load_i8(vm.mem_map, 0x6000U + k.reinterpret_as_uint()),
      Ok(0x42),
    )
  }
  // Memcpy 0x6010 <- 0x6000, n=4：栈序 dest,src,n
  vm.ip = 0
  vm.stack.clear()
  vm.error = ""
  // Memcpy 压入序：n → src → dest（dest 栈顶，弹参序 dest/src/n）
  vm.load_program(
    code_of([
      instr(PushConst, 4),
      instr(PushConst, 0x6000),
      instr(PushConst, 0x6010),
      instr(Memcpy, 0),
    ]),
  )
  let ret2 = vm.run()
  assert_eq(ret2, 0x6010)
  assert_eq(vm.memory.load_u32(vm.mem_map, 0x6010U), Ok(0x42424242U))
}

///|
/// 段二 fail loud：F/D/Q 与控制流族到达即 trap（登记文案含 opcode 名）。
test "exec_unwired_opcodes_fail_loud" {
  let vm = VitroVM::new()
  vm.load_program(code_of([instr(AddD, 0)]))
  let r = vm.step()
  assert_true(r is Trap)
  assert_true(vm.error.contains("浮点/长整型族（AddD）"))
  let vm2 = VitroVM::new()
  vm2.load_program(code_of([instr(Jump, 3)]))
  let r2 = vm2.step()
  assert_true(r2 is Trap)
  assert_true(vm2.error.contains("控制流族（Jump）"))
  // C# 三件（CS 批语义，零发射契约）
  let vm3 = VitroVM::new()
  vm3.load_program(code_of([instr(Throw, 0)]))
  let r3 = vm3.step()
  assert_true(r3 is Trap)
  assert_true(vm3.error.contains("C# 异常指令被执行（Throw）"))
}

///|
/// **P1-1 符号扩展锚（审阅修复批）**：PushConst(-1) 落栈必须是
/// 0xFFFFFFFFFFFFFFFF（oracle `as u64` 符号扩展；修复前本实现零扩展落
/// 0x00000000FFFFFFFF）。栈顶原始索引进 TrapBounds 的负索引分支——
/// 诊断文案必须给「索引 -1」而非「索引 4294967295」。
test "exec_push_const_negative_sign_extension" {
  let vm = VitroVM::new()
  vm.load_program(code_of([instr(PushConst, -1)]))
  ignore(vm.step())
  assert_eq(vm.stack[0], 18446744073709551615UL)
}

///|
/// P1-1 文案锚：负索引经 TrapBounds 字面量形态（operand=-4 → size 4）
/// 诊断「索引 -1 超出了合法范围 0~3」（栈上符号扩展位模式 → i64 解释 -1）。
test "exec_trap_bounds_negative_index_diag" {
  let vm = VitroVM::new()
  vm.load_program(code_of([instr(PushConst, -1), instr(TrapBounds, -4)]))
  ignore(vm.step())
  let r = vm.step()
  assert_true(r is Trap)
  assert_true(
    vm.error.contains(
      "🚫 数组越界：索引 -1 超出了合法范围 0~3。",
    ),
  )
}

///|
/// P1-1 位模式锚：SplitQ 拆 -1 的两个半字均符号扩展（oracle 同形——
/// 修复前零扩展落 0x00000000FFFFFFFF ×2）。
test "exec_split_q_negative_halves_sign_extended" {
  let vm = VitroVM::new()
  vm.load_program(
    code_of([
      instr(PushConstQ, 0), // 占位（PushConstQ 段二接线——改用直接压栈形态）
    ]),
  )
  // 直接压 -1 再 SplitQ（绕过未接线的常量池指令）
  vm.stack.clear()
  vm.stack.push(18446744073709551615UL)
  vm.ip = 0
  vm.load_program(code_of([instr(SplitQ, 0)]))
  let r = vm.step()
  assert_true(r is Ok)
  assert_eq(vm.stack.length(), 2)
  assert_eq(vm.stack[0], 18446744073709551615UL)
  assert_eq(vm.stack[1], 18446744073709551615UL)
}

///|
/// Neg 溢出拦截锚（P3-2 补锚：修复前该分支无测试覆盖）。
test "exec_neg_overflow_traps" {
  let vm = VitroVM::new()
  vm.load_program(code_of([instr(PushConst, -2147483648), instr(Neg, 0)]))
  ignore(vm.step())
  let r = vm.step()
  assert_true(r is Trap)
  assert_true(vm.error.contains("整数取反溢出。-INT_MIN"))
}

///|
/// 局部访存上下界预检锚（P3-2 补锚）：operand 使地址越过 NULL 陷阱区 /
/// 上界 → 「LoadLocal: 地址越界」预检文案（非 MemFault 渲染路径）。
test "exec_local_bounds_precheck_traps" {
  // 下界：locals_base(0x8000) + operand(-0x8000) = 0 → NULL 区
  let vm = VitroVM::new()
  vm.call_stack.push(CallFrame::{
    return_ip: Some(0),
    locals_base: 0x8000U,
    local_count: 1,
    func_name: "main",
    original_stack_top: 0,
    caller_line: 0,
    local_buffers: [],
  })
  vm.load_program(code_of([instr(LoadLocal, -32768)]))
  let r = vm.step()
  assert_true(r is Trap)
  assert_true(vm.error.contains("LoadLocal: 地址越界"))
  // 上界：locals_base(0xFFFF0) + operand(0x20) 越过 MEM_SIZE
  let vm2 = VitroVM::new()
  vm2.call_stack.push(CallFrame::{
    return_ip: Some(0),
    locals_base: 0xFFFF0U,
    local_count: 1,
    func_name: "main",
    original_stack_top: 0,
    caller_line: 0,
    local_buffers: [],
  })
  vm2.load_program(code_of([instr(StoreLocalD, 32)]))
  let r2 = vm2.step()
  assert_true(r2 is Trap)
  assert_true(vm2.error.contains("StoreLocalD: 地址越界"))
}

///|
/// UAdd 负值符号扩展锚：UAdd(-1, -1) = -2（回绕）→ 落栈 0xFFFF...FF
/// 的 i64 位形（修复前零扩展落 0x00000000FFFFFFFE）。
test "exec_uadd_negative_sign_extension" {
  let vm = VitroVM::new()
  vm.load_program(
    code_of([instr(PushConst, -1), instr(PushConst, -1), instr(UAdd, 0)]),
  )
  let _ = vm.run()
  assert_eq(vm.stack[0], 18446744073709551614UL) // -2 符号扩展
}

///|
/// BitAnd 负结果符号扩展锚：-1 & 0xFFFFFFF0 = 0xFFFFFFF0（负）→ 落栈
/// 0xFFFFFFFFFFFFFFF0（修复前零扩展落 0x00000000FFFFFFF0）。
test "exec_bitand_negative_result_sign_extended" {
  let vm = VitroVM::new()
  vm.load_program(
    code_of([instr(PushConst, -1), instr(PushConst, -16), instr(BitAnd, 0)]),
  )
  let _ = vm.run()
  assert_eq(vm.stack[0], 18446744073709551600UL) // 0xFFFF...FFF0
}

///|
/// 二轮审阅补漏锚：LoadMem 负值符号扩展（与 LoadLocal 同型——修复前
/// 零扩展落 4294967295）。种子经 StoreMem 写 -1 再 LoadMem 读回。
test "exec_loadmem_negative_sign_extension" {
  let vm = VitroVM::new()
  // 堆区直接写 -1（绕过未接线的 host malloc——受检直写 0x6000）
  guard vm.memory.store_u32(vm.mem_map, 0x6000U, 0xFFFFFFFFU) is Ok(_) else {
    fail("种子写入必须成功")
  }
  vm.load_program(code_of([instr(PushConst, 0x6000), instr(LoadMem, 0)]))
  let r = vm.run()
  assert_eq(r, -1) // run 返回低 32 位符号解释
  assert_eq(vm.stack[0], 18446744073709551615UL) // 栈上位模式 = 符号扩展
}

///|
/// 二轮审阅补漏锚（**可达文案分叉**）：LoadMem 读出 -1 → TrapBounds(-4)
/// 诊断必须给「索引 -1」（a[*p] 形状——修复前给「索引 4294967295」）。
test "exec_loadmem_trap_bounds_negative_diag" {
  let vm = VitroVM::new()
  guard vm.memory.store_u32(vm.mem_map, 0x6000U, 0xFFFFFFFFU) is Ok(_) else {
    fail("种子写入必须成功")
  }
  vm.load_program(
    code_of([instr(PushConst, 0x6000), instr(LoadMem, 0), instr(TrapBounds, -4)]),
  )
  ignore(vm.step())
  ignore(vm.step())
  let r = vm.step()
  assert_true(r is Trap)
  assert_true(
    vm.error.contains(
      "🚫 数组越界：索引 -1 超出了合法范围 0~3。",
    ),
  )
}

///|
/// 二轮审阅补漏锚：Div/Mod 负商/负余数符号扩展（-7/2 = -3、-7%2 = -1；
/// 修复前零扩展落 4294967293 / 4294967295）。
test "exec_div_mod_negative_sign_extension" {
  let vm = VitroVM::new()
  vm.load_program(
    code_of([instr(PushConst, -7), instr(PushConst, 2), instr(Div, 0)]),
  )
  let _ = vm.run()
  assert_eq(vm.stack[0], 18446744073709551613UL) // -3 符号扩展
  let vm2 = VitroVM::new()
  vm2.load_program(
    code_of([instr(PushConst, -7), instr(PushConst, 2), instr(Mod, 0)]),
  )
  let _ = vm2.run()
  assert_eq(vm2.stack[0], 18446744073709551615UL) // -1 符号扩展
}
