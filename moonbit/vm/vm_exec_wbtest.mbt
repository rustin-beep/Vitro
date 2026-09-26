///|
fn codes_to_str(bytes : Bytes) -> String {
  let codes : Array[Int] = []
  for i = 0; i < bytes.length(); i = i + 1 {
    codes.push(bytes[i].to_int())
  }
  let sb = StringBuilder::new()
  for c in codes {
    sb.write_char(c.unsafe_to_char())
  }
  sb.to_string()
}

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
    original_stack_top: 0U,
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
    original_stack_top: 0U,
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
/// fail loud 剩余面（控制流接线后）：CallHost 的 host 分发（批三号）与
/// C# 三件（CS 批）。
test "exec_unwired_opcodes_fail_loud" {
  let vm = VitroVM::new()
  vm.load_program(code_of([instr(CallHost, 200)])) // 路由外 id
  let r = vm.step()
  assert_true(r is Trap)
  assert_true(vm.error.contains("CallHost 未知 id=200"))
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
    original_stack_top: 0U,
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
    original_stack_top: 0U,
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

///|
/// F 族（f32）锚：位模式进出 + 除零 trap + 比较 IEEE 精确。
/// 1.5f 位 = 0x3FC00000 = 1069547520；2.5f + 1.25f = 3.75f（0x40700000）。
test "exec_float_family_arith_and_divzero" {
  let vm = VitroVM::new()
  // PushConstF(1069547520)=1.5f；AddF(1.5f + 1.25f(0x3FA00000=1066197248)) = 2.75f
  vm.load_program(
    code_of([
      instr(PushConstF, 1069547520),
      instr(PushConstF, 1067450368),
      instr(AddF, 0),
    ]),
  )
  let r = vm.run()
  // 2.75f 位 = 0x40300000 = 1076887552（python struct.pack 实算）；run 返回低 32 位符号解释（正数同值）
  assert_eq(r, 1076887552)
  assert_eq(vm.stack[0], 1076887552UL)
  // 除零 → 教学 trap
  let vm2 = VitroVM::new()
  vm2.load_program(
    code_of([
      instr(PushConstF, 1065353216), // 1.0f
      instr(PushConstF, 0), // 0.0f
      instr(DivF, 0),
    ]),
  )
  ignore(vm2.step())
  ignore(vm2.step())
  let r2 = vm2.step()
  assert_true(r2 is Trap)
  assert_true(vm2.error.contains("浮点数除以零"))
}

///|
/// D 族（f64）锚：常量池 + 比较 IEEE 精确（0.1+0.2 != 0.3——浮点教学
/// 核心一课，E1 裁定无容差）。
test "exec_double_family_pool_and_ieee_compare" {
  let vm = VitroVM::new()
  vm.set_f64_constants([0.1, 0.2, 0.3])
  // (0.1 + 0.2) == 0.3 → 0（IEEE 精确比较判假）
  vm.load_program(
    code_of([
      instr(PushConstD, 0),
      instr(PushConstD, 1),
      instr(AddD, 0),
      instr(PushConstD, 2),
      instr(EqD, 0),
    ]),
  )
  let r = vm.run()
  assert_eq(r, 0)
  // 常量索引越界 → trap
  let vm2 = VitroVM::new()
  vm2.set_f64_constants([1.5])
  vm2.load_program(code_of([instr(PushConstD, 5)]))
  let r2 = vm2.step()
  assert_true(r2 is Trap)
  assert_true(vm2.error.contains("f64常量索引越界: 5"))
}

///|
/// Q 族（i64）锚：常量池 + 回绕（不 trap——与 i32 族教学 trap 分口径）+
/// LLONG_MIN/-1 拦截 + CastQ2I 截断。
test "exec_longlong_family_wrap_and_guards" {
  let vm = VitroVM::new()
  // LLONG_MAX + 1 = LLONG_MIN（回绕不 trap）
  vm.set_i64_constants([9223372036854775807L, 1L])
  vm.load_program(
    code_of([instr(PushConstQ, 0), instr(PushConstQ, 1), instr(AddQ, 0)]),
  )
  let r = vm.step()
  let r2 = vm.step()
  let r3 = vm.step()
  assert_true(r is Ok)
  assert_true(r2 is Ok)
  assert_true(r3 is Ok)
  assert_eq(vm.stack[0].reinterpret_as_int64(), -9223372036854775808L)
  // DivQ LLONG_MIN / -1 → trap
  let vm2 = VitroVM::new()
  vm2.stack.push((-9223372036854775808L).reinterpret_as_uint64())
  vm2.stack.push((-1L).reinterpret_as_uint64())
  vm2.load_program(code_of([instr(DivQ, 0)]))
  let r4 = vm2.step()
  assert_true(r4 is Trap)
  assert_true(vm2.error.contains("long long 除法溢出"))
  // CastQ2I 截断：4294967301L → 5（低 32 位）
  let vm3 = VitroVM::new()
  vm3.stack.push((4294967296L + 5L).reinterpret_as_uint64())
  vm3.load_program(code_of([instr(CastQ2I, 0)]))
  let _ = vm3.run()
  assert_eq(vm3.stack[0], 5UL)
}

///|
/// Cast 族锚：CastI2D / CastD2I 饱和 / CastF2I 饱和（探针实证
/// %f64_to_i32_saturate = Rust as i32）。
test "exec_cast_saturate_semantics" {
  let vm = VitroVM::new()
  vm.stack.push(2147483647.5.reinterpret_as_uint64())
  vm.load_program(code_of([instr(CastD2I, 0)]))
  let _ = vm.run()
  assert_eq(vm.stack[0], 2147483647UL) // 饱和到 MAX 而非回绕
  let vm2 = VitroVM::new()
  vm2.stack.push((-2147483648.9).reinterpret_as_uint64())
  vm2.load_program(code_of([instr(CastD2I, 0)]))
  let _ = vm2.run()
  assert_eq(vm2.stack[0].to_int(), -2147483648) // 饱和到 MIN
  let vm3 = VitroVM::new()
  vm3.load_program(code_of([instr(PushConst, 7), instr(CastI2D, 0)]))
  let _ = vm3.run()
  assert_eq(vm3.stack[0].reinterpret_as_double(), 7.0)
}

///|
/// 控制流锚：Call/Ret 完整往返——寄存器保存（func_table 稀疏表 + ip 跳转
/// + 帧压栈 + 参数落局部区 + 返回值压栈 + 栈顶恢复）。
test "exec_call_ret_roundtrip" {
  let vm = VitroVM::new()
  // 函数 3：double(x) = x*2 —— ip=10, local_count=4（**字节单位且 4 对齐**——
  // codegen 契约；1 个 int 参数 = 4 字节）
  assert_true(
    vm.register_function(3, @bytecode.FuncMeta::{
      ip: 10,
      arg_count: 1,
      param_count: 1,
      local_count: 4,
      param_sizes: [1],
      return_type: @ast.Type::Int(false, false),
      is_variadic: false,
      local_buffers: [],
    }),
  )
  assert_true(vm.register_function_name(3, "double"))
  // 主流程（ip 0..）：PushConst 21; Call 3; [fn 体 ip10: LoadLocal 0; PushConst 2; Mul; Ret]
  let code : Array[@opcode.Instruction] = []
  code.push(instr(PushConst, 21))
  code.push(instr(Call, 3))
  code.push(instr(Ret, 0))
  while code.length() < 10 {
    code.push(instr(Nop, 0))
  }
  code.push(instr(LoadLocal, 0))
  code.push(instr(PushConst, 2))
  code.push(instr(Mul, 0))
  code.push(instr(Ret, 0))
  vm.load_program(code)
  let r = vm.run()
  assert_eq(r, 42)
  // 帧已弹空、栈只余返回值
  assert_eq(vm.call_stack.length(), 0)
  assert_eq(vm.stack.length(), 1)
}

///|
/// 控制流锚：JumpIfZero 回边循环——0+1+2+...+4 = 10（倒计数形状）。
test "exec_jump_if_zero_loop" {
  let vm = VitroVM::new()
  // 布局（手工汇编）：
  // 0: PushConst 0        ; sum
  // 1: StoreGlobal 0      ; sum -> g0
  // 2: PushConst 4        ; i = 4（倒计数）
  // 3: StoreGlobal 4      ; i -> g4
  // 4: LoadGlobal 4       ; loop: i
  // 5: JumpIfZero 14      ; i==0 → 出口
  // 6: LoadGlobal 0       ; sum
  // 7: LoadGlobal 4       ; i
  // 8: Add
  // 9: StoreGlobal 0      ; sum += i
  // 10: LoadGlobal 4
  // 11: PushConst 1
  // 12: Sub
  // 13: StoreGlobal 4     ; i -= 1
  // 13 后接 Jump 4？—— 直接顺序回 4 不行（需显式 Jump）。改布局：12: Sub; 13: StoreGlobal 4; 14: Jump 4；出口挪 15
  let code : Array[@opcode.Instruction] = []
  code.push(instr(PushConst, 0))
  code.push(instr(StoreGlobal, 0))
  code.push(instr(PushConst, 4))
  code.push(instr(StoreGlobal, 4))
  // loop head @4
  code.push(instr(LoadGlobal, 4))
  code.push(instr(JumpIfZero, 15))
  code.push(instr(LoadGlobal, 0))
  code.push(instr(LoadGlobal, 4))
  code.push(instr(Add, 0))
  code.push(instr(StoreGlobal, 0))
  code.push(instr(LoadGlobal, 4))
  code.push(instr(PushConst, 1))
  code.push(instr(Sub, 0))
  code.push(instr(StoreGlobal, 4))
  code.push(instr(Jump, 4))
  // exit @16: LoadGlobal 0
  code.push(instr(LoadGlobal, 0))
  vm.load_program(code)
  let r = vm.run()
  assert_eq(r, 10)
  assert_eq(vm.memory.load_u32(vm.mem_map, @bytecode.GLOBAL_START), Ok(10U))
}

///|
/// 控制流锚：调用深度上限（V-P1-10——递归无终止条件时可控 trap）。
test "exec_call_depth_limit_traps" {
  let vm = VitroVM::new()
  vm.set_call_depth_limit(8)
  // 函数 0：无限自递归 f(){ f(); }
  assert_true(
    vm.register_function(0, @bytecode.FuncMeta::{
      ip: 1,
      arg_count: 0,
      param_count: 0,
      local_count: 0,
      param_sizes: [],
      return_type: @ast.Type::Void(false),
      is_variadic: false,
      local_buffers: [],
    }),
  )
  let code : Array[@opcode.Instruction] = []
  code.push(instr(Call, 0)) // 0: 入口
  code.push(instr(Call, 0)) // 1: f 体 = 自递归
  code.push(instr(Ret, 0))
  vm.load_program(code)
  let r = vm.run()
  // 深度超限 → Trap（run 返 0）
  assert_eq(r, 0)
  assert_true(vm.error.contains("调用深度超过上限（8 层）"))
}

///|
/// 控制流锚：CallPtr（函数指针经栈传索引调用）。
test "exec_call_ptr" {
  let vm = VitroVM::new()
  assert_true(
    vm.register_function(5, @bytecode.FuncMeta::{
      ip: 4,
      arg_count: 0,
      param_count: 0,
      local_count: 0,
      param_sizes: [],
      return_type: @ast.Type::Int(false, false),
      is_variadic: false,
      local_buffers: [],
    }),
  )
  let code : Array[@opcode.Instruction] = []
  code.push(instr(PushConst, 5)) // 函数索引
  code.push(instr(CallPtr, 0))
  code.push(instr(Ret, 0))
  code.push(instr(Nop, 0))
  code.push(instr(PushConst, 7)) // fn 体 @4
  code.push(instr(Ret, 0))
  vm.load_program(code)
  let r = vm.run()
  assert_eq(r, 7)
  // 越界索引 → trap
  let vm2 = VitroVM::new()
  vm2.load_program(code_of([instr(PushConst, 999), instr(CallPtr, 0)]))
  ignore(vm2.step())
  let r2 = vm2.step()
  assert_true(r2 is Trap)
  assert_true(vm2.error.contains("CallPtr: 函数指针索引 999 越界"))
}

///|
/// 控制流锚：宿主回调哨兵（return_ip = None 的帧 Ret → 恢复栈顶 +
/// 压返回值 + Finished——qsort/bsearch 回调协议的 VM 侧形态）。
test "exec_host_callback_sentinel_ret" {
  let vm = VitroVM::new()
  let top_before = vm.mem_stack_top
  vm.mem_stack_top = 0xFF00U // 模拟回调现场的较低栈顶
  vm.call_stack.push(CallFrame::{
    return_ip: None, // 哨兵
    locals_base: 0xFF00U,
    local_count: 0,
    func_name: "cmp",
    original_stack_top: 0xFF40U,
    caller_line: 0,
    local_buffers: [],
  })
  vm.load_program(
    code_of([
      instr(PushConst, -1), // cmp 返回 -1
      instr(Ret, 0),
    ]),
  )
  ignore(vm.step())
  let r = vm.step()
  assert_true(r is Finished) // 哨兵帧 Ret = 整个宿主回调收尾
  assert_eq(vm.mem_stack_top, 0xFF40U) // original_stack_top 恢复
  assert_eq(vm.stack.length(), 1)
  assert_eq(vm.stack[0].reinterpret_as_int64(), -1L) // 返回值符号扩展压栈
  ignore(top_before)
}

///|
/// 控制流锚：RetVoid 不弹返回值 + 顶层 Ret/RetVoid = Finished。
test "exec_retvoid_and_top_level" {
  let vm = VitroVM::new()
  vm.load_program(code_of([instr(Ret, 0)]))
  let r = vm.step()
  assert_true(r is Finished)
  let vm2 = VitroVM::new()
  vm2.load_program(code_of([instr(PushConst, 1), instr(RetVoid, 0)]))
  ignore(vm2.step())
  let r2 = vm2.step()
  assert_true(r2 is Finished)
  assert_eq(vm2.stack.length(), 1) // RetVoid 不取返回值
}

///|
/// 控制流锚：Jump 目标越界 trap（负值与超长两形态）。
test "exec_jump_out_of_range_traps" {
  let vm = VitroVM::new()
  vm.load_program(code_of([instr(Jump, 99)]))
  let r = vm.step()
  assert_true(r is Trap)
  assert_true(vm.error.contains("Jump 目标越界：99"))
}

///|
/// 红锚（2026-09-26 e1_va_copy 缺陷批）：**void host 函数调用后值栈必须
/// 平衡**——`no_reply()`（value=None）语义 = 不压值，apply_reply 曾无条件
/// 压 0（`None => 0UL`），每次调用泄露一个幽灵 0；该泄露只在「调用后栈上
/// 仍有更早压入的元素待读」的嵌套形态暴露（e1_va_copy 的
/// `printf("%.1f %.1f", sum_twice(2,...), sum_twice(3,...))` 形态），
/// 裸调用（独立语句）静默无害——故 30 例抽样零覆盖、全量 601 首轮暴露。
/// 本锚用 va_end（id 142，Rust `misc.rs:587` 弹 1 不 push——纯 pop 不碰
/// 内存，无 trap 面）直驱：压 1 实参 → CallHost 142 → 栈必须回到 0
/// （修复前为 1）。
test "host_void_call_stack_balance" {
  let vm = VitroVM::new()
  vm.load_program(
    code_of([
      instr(PushConst, 0), // va_end 的 ap_addr 实参（只被 pop，不解引用）
      instr(CallHost, 142),
      instr(PushConst, 4242),
    ]),
  )
  let r = vm.run()
  assert_eq(r, 4242)
  // 修复前栈为 [幽灵0, 4242]（长度 2）；修复后仅剩末尾哨兵 [4242]
  assert_eq(
    vm.stack.length(),
    1,
    msg="void host 调用后不得残留幽灵值",
  )
}

///|
/// 批三号第一段锚：ctype/math/内存族/exit 族经 CallHost 分发的完整协议。
/// host id 来自 Rust host_func_id 常量表（ctype 42-55 等）。
test "host_dispatch_ctype_math_exit" {
  // isdigit('5') = 1
  let vm = VitroVM::new()
  vm.load_program(
    code_of([instr(PushConst, '5'.to_int()), instr(CallHost, 42)]),
  )
  let r = vm.run()
  assert_eq(r, 1)
  // sqrt(2.0) 位往返（f64 位模式进出）
  let vm2 = VitroVM::new()
  vm2.stack.push(2.0.reinterpret_as_uint64())
  vm2.load_program(code_of([instr(CallHost, 72)]))
  let _ = vm2.run()
  assert_eq(vm2.stack[0].reinterpret_as_double(), 1.4142135623730951)
  // pow 弹参序：pow(2.0, 10.0) = 1024（x 先弹——栈序 y 先压 x 后压）
  let vm3 = VitroVM::new()
  vm3.load_program(
    code_of([
      instr(PushConstD, 0), // y = 10.0（常量池占位——直接压栈更直接，改用下方直压）
    ]),
  )
  vm3.stack.clear()
  vm3.stack.push(10.0.reinterpret_as_uint64()) // y（先压）
  vm3.stack.push(2.0.reinterpret_as_uint64()) // x（后压=栈顶）
  vm3.ip = 0
  vm3.load_program(code_of([instr(CallHost, 73)]))
  let _ = vm3.run()
  assert_eq(vm3.stack[0].reinterpret_as_double(), 1024.0)
  // atan2 弹参序（非对称实参——三轮审阅 P3：对称实参零判别力）：
  // atan2(y=2, x=1) = 1.1071…（y 先弹——栈序 x 先压 y 后压；翻转会得 0.4636…）
  let vm4 = VitroVM::new()
  vm4.stack.push(1.0.reinterpret_as_uint64()) // x（先压）
  vm4.stack.push(2.0.reinterpret_as_uint64()) // y（后压=栈顶）
  vm4.load_program(code_of([instr(CallHost, 111)]))
  let _ = vm4.run()
  assert_eq(vm4.stack[0].reinterpret_as_double(), 1.1071487177940904)
  // fmod 弹参序（非对称，三轮审阅 P1-1：修复前算成 fmod(7.5,2)=1.5）：
  // fmod(x=2, y=7.5) = 2（先弹 x——栈序 y 先压 x 后压）
  let vm6 = VitroVM::new()
  vm6.stack.push(7.5.reinterpret_as_uint64()) // y（先压）
  vm6.stack.push(2.0.reinterpret_as_uint64()) // x（后压=栈顶）
  vm6.load_program(code_of([instr(CallHost, 105)]))
  let _ = vm6.run()
  assert_eq(vm6.stack[0].reinterpret_as_double(), 2.0)
  // exit(42)：finished + exit_code
  let vm5 = VitroVM::new()
  vm5.load_program(code_of([instr(PushConst, 42), instr(CallHost, 38)]))
  let r5 = vm5.step() // PushConst
  let r6 = vm5.step() // CallHost：exit 当步 Ok（finished 已置位）
  assert_true(r5 is Ok)
  assert_true(r6 is Ok)
  assert_true(vm5.finished)
  assert_eq(vm5.exit_code, 42)
  let r7 = vm5.step() // 此后每步 Finished
  assert_true(r7 is Finished)
}

///|
/// malloc/free 经 CallHost：分配 → 值栈弹 size → 地址压回 → free 三态。
test "host_dispatch_malloc_free" {
  let vm = VitroVM::new()
  vm.load_program(code_of([instr(PushConst, 16), instr(CallHost, 2)]))
  let r = vm.run()
  // 堆起点（无 argv/global_data_end 推移 = HEAP_START 0x5000）
  assert_eq(r, 0x5000)
  assert_eq(vm.mem_map.regions_len(), 1)
  // free：Double-Free → E3061 trap
  vm.stack.push(0x5000UL)
  vm.ip = 0
  vm.error = ""
  vm.load_program(code_of([instr(CallHost, 3)]))
  let _ = vm.run() // 第一次 free 正常
  assert_eq(vm.error, "")
  vm.stack.push(0x5000UL)
  vm.ip = 0
  vm.error = ""
  vm.load_program(code_of([instr(CallHost, 3)]))
  let r2 = vm.run()
  assert_eq(r2, 0)
  // E3061 Double-Free（三轮审阅 P3：此前 || !error.is_empty() 的兜底使
  // 前四项成死代码——收紧为精确断言）
  assert_true(vm.error.contains("E3061"))
  assert_true(
    vm.error.contains("重复释放") ||
    vm.error.contains("Double-Free") ||
    vm.error.contains("已被释放"),
  )
  // 精确文案由 host 层锚覆盖——此处锚定「二次 free 必产 trap」
  assert_true(!vm.error.is_empty())
}

///|
/// abort/assert_fail/unreachable 三件。
test "host_dispatch_exit_family" {
  let vm = VitroVM::new()
  vm.load_program(code_of([instr(CallHost, 116)]))
  let r = vm.step() // CallHost：abort 当步 Ok
  assert_true(r is Ok)
  assert_true(vm.finished)
  assert_eq(vm.exit_code, 134)
  let r_next = vm.step()
  assert_true(r_next is Finished)
  assert_true(
    vm.output.has_note(@utf8.encode("[abort] 程序异常终止 (SIGABRT)\n")),
  )
  let vm2 = VitroVM::new()
  vm2.load_program(code_of([instr(CallHost, 125)]))
  let r2 = vm2.step() // assert_fail 当步 Ok + finished
  assert_true(r2 is Ok)
  assert_true(vm2.finished)
  assert_eq(vm2.exit_code, 1)
  let r2_next = vm2.step()
  assert_true(r2_next is Finished)
  let vm3 = VitroVM::new()
  vm3.load_program(code_of([instr(CallHost, 144)]))
  let r3 = vm3.step()
  assert_true(r3 is Trap)
  assert_true(vm3.error.contains("unreachable"))
}

///|
/// putchar/OUTPUT 输出族 + rand/srand。
test "host_dispatch_output_and_rand" {
  let vm = VitroVM::new()
  vm.load_program(
    code_of([instr(PushConst, 'A'.to_int()), instr(CallHost, 34)]),
  )
  let _ = vm.run()
  assert_eq(vm.output.chunks_of(@host.OutputKind::Stdout).length(), 1)
  // rand 直调单元锚（**遮蔽死面的单元语义锚**——三轮审阅 P2-2：真实程序
  // 里 rand 被 Bytecode Libc 预注册遮蔽走 `Call 1014`（__rand_seed=1，
  // 首值 16838）；本臂是 host 直调形态的 LCG seed 42 首值 3611——与
  // host 层锚同值，判 host_rand 接线本身）
  let vm2 = VitroVM::new()
  vm2.load_program(code_of([instr(CallHost, 35)]))
  let r2 = vm2.run()
  assert_eq(r2, 3611)
}

///|
/// NegF 零符号锚（三轮审阅 P1-2）：-0.0f 位 = 0x80000000 = 2147483648
/// （修复前 0.0f - 0.0f = +0.0f 丢符号落 0）。
test "exec_negf_zero_sign" {
  let vm = VitroVM::new()
  vm.stack.push(0UL) // +0.0f 位
  vm.load_program(code_of([instr(NegF, 0)]))
  let r = vm.step()
  assert_true(r is Ok)
  assert_eq(vm.stack[0], 2147483648UL) // 0x80000000（符号位保留）
}

///|
/// 堆耗尽附注去重锚（三轮审阅 P2-1）：连续多次超限 malloc 只产一条
/// heap_exhausted 附注（oracle report_heap_exhausted 的 contains 去重；
/// 修复前每次都推——3 次给 3 条）。
test "host_dispatch_heap_exhausted_note_dedup" {
  let vm = VitroVM::new()
  // 巨尺寸 malloc（> 1MB）→ 堆耗尽 → NULL + 附注；连续三次
  for k = 0; k < 3; k = k + 1 {
    vm.ip = 0
    vm.error = ""
    vm.load_program(code_of([instr(PushConst, 2000000), instr(CallHost, 2)]))
    let _ = vm.run()
    assert_eq(vm.stack[vm.stack.length() - 1], 0UL) // NULL
  }
  let notes = vm.output.chunks_of(@host.OutputKind::Note)
  let exhausted = notes.filter(fn(b) { b.length() > 0 && b[0] == b'[' })
  assert_eq(exhausted.length(), 1, msg="堆耗尽附注必须去重到 1 条")
}

///|
/// 二段分发锚：字符串族（strlen/strcmp 经 CallHost 全协议）。
test "host2_string_family" {
  // 堆区写 "hi\0" → strlen = 2
  let vm = VitroVM::new()
  guard vm.memory.store_u32(vm.mem_map, 0x6000U, 0x00006968U) is Ok(_) else {
    fail("种子")
  }
  vm.load_program(code_of([instr(PushConst, 0x6000), instr(CallHost, 30)]))
  let r = vm.run()
  assert_eq(r, 2)
  // strcmp("hi","hi") = 0
  let vm2 = VitroVM::new()
  guard vm2.memory.store_u32(vm2.mem_map, 0x6000U, 0x00006968U) is Ok(_) else {
    fail("种子")
  }
  vm2.load_program(
    code_of([
      instr(PushConst, 0x6000),
      instr(PushConst, 0x6000),
      instr(CallHost, 32),
    ]),
  )
  let r2 = vm2.run()
  assert_eq(r2, 0)
}

///|
/// 二段锚：义务②（strcpy 栈缓冲溢出——spans 从 call_stack 展平）。
/// 帧 local_buffers 含 buf@offset4 size8（base 0x8000 → span 0x8004..0x800C）；
/// strcpy 写 12 字节（"hello world"+NUL）到 0x8004 → E3070 trap。
test "host2_strcpy_stack_buffer_guard" {
  let vm = VitroVM::new()
  guard vm.memory.store_u32(vm.mem_map, 0x6000U, 0x6C6C6568U) is Ok(_) else {
    fail("种子 hi..")
  }
  // 造 12 字节长串 "aaaaaaaaaaa\0" @0x6000
  for k = 0; k < 11; k = k + 1 {
    guard vm.memory.store_i8(
        vm.mem_map,
        0x6000U + k.reinterpret_as_uint(),
        'a'.to_int(),
      )
      is Ok(_) else {
      fail("种子")
    }
  }
  guard vm.memory.store_i8(vm.mem_map, 0x600BU, 0) is Ok(_) else { fail("NUL") }
  vm.call_stack.push(CallFrame::{
    return_ip: Some(0),
    locals_base: 0x8000U,
    local_count: 12,
    func_name: "main",
    original_stack_top: 0x100000U,
    caller_line: 0,
    local_buffers: [@bytecode.LocalBuffer::{ offset: 4, size: 8, name: "buf", }],
  })
  vm.load_program(
    code_of([
      instr(PushConst, 0x6000), // src（先压）
      instr(PushConst, 0x8004), // dest（后压=栈顶；span 内）
      instr(CallHost, 31),
    ]),
  )
  let r = vm.run()
  assert_eq(r, 0)
  assert_true(
    vm.error.contains("E3070") || vm.error.contains("栈上缓冲区"),
  )
}

///|
/// 二段锚：义务③（strtol 的 errno 地址从符号表解析——无符号时 None 直通）。
/// strtol("42", NULL, 10) = 42。
test "host2_strtol_basic" {
  let vm = VitroVM::new()
  guard vm.memory.store_u32(vm.mem_map, 0x6000U, 0x00003234U) is Ok(_) else {
    fail("种子 '42'")
  } // 42
  guard vm.memory.store_i8(vm.mem_map, 0x6002U, 0) is Ok(_) else { fail("NUL") }
  vm.load_program(
    code_of([
      instr(PushConst, 10), // base（先压——C 从右往左）
      instr(PushConst, 0), // endptr = NULL
      instr(PushConst, 0x6000), // str（栈顶=首实参）
      instr(CallHost, 117),
    ]),
  )
  let r = vm.run()
  assert_eq(r, 42)
}

///|
/// 二段锚：VFS 族（fopen/fwrite/fclose/fread 全协议 + VFS 状态在 vm）。
test "host2_vfs_family" {
  let vm = VitroVM::new()
  // 写路径串 "f.txt" 与模式 "w" 到堆
  for pair in [("f.txt", 0x6000U), ("w", 0x6010U)] {
    let bytes = @utf8.encode(pair.0)
    for i = 0; i < bytes.length(); i = i + 1 {
      guard vm.memory.store_i8(
          vm.mem_map,
          pair.1 + i.reinterpret_as_uint(),
          bytes[i].to_int(),
        )
        is Ok(_) else {
        fail("路径种子")
      }
    }
    guard vm.memory.store_i8(
        vm.mem_map,
        pair.1 + bytes.length().reinterpret_as_uint(),
        0,
      )
      is Ok(_) else {
      fail("NUL")
    }
  }
  // fopen("f.txt","w") → FILE* 留栈（堆上 4 字节存 fd——FILE* 协议），
  // 续压 nmemb/size/buf 后 fwrite——一次程序完成「开→写」全协议
  for k = 0; k < 3; k = k + 1 {
    guard vm.memory.store_i8(
        vm.mem_map,
        0x7000U + k.reinterpret_as_uint(),
        'x'.to_int(),
      )
      is Ok(_) else {
      fail("x")
    }
  }
  vm.load_program(
    code_of([
      instr(PushConst, 0x6010), // mode（先压——C 从右往左）
      instr(PushConst, 0x6000), // path（栈顶=首实参）
      instr(CallHost, 60), // → FILE* 在栈上（堆地址，read_fd 从中取 fd）
      instr(PushConst, 3), // nmemb
      instr(PushConst, 1), // size
      instr(PushConst, 0x7000), // buf（栈顶=首实参）
      instr(CallHost, 62),
    ]),
  )
  let r = vm.run()
  assert_eq(r, 3) // fwrite 返回写入项数
  assert_eq(vm.error, "")
}

///|
/// 二段锚：va 族三件直通（va_start/va_arg/va_end 协议——最小闭环）。
test "host2_va_family" {
  let vm = VitroVM::new()
  // va_start(last=0x8004, n_fixed=1, n_total=3) → 写 va_list 结构
  vm.load_program(
    code_of([
      instr(PushConst, 3), // n_total（先压）
      instr(PushConst, 1), // n_fixed
      instr(PushConst, 0x8004), // last_param（栈顶=首实参）
      instr(CallHost, 140),
    ]),
  )
  let r = vm.run()
  assert_eq(r, 0) // va_start 返 0（无错误）
  assert_eq(vm.error, "")
} ///|///|///|///|
/// 三段锚：bsearch 命中与未命中（经 call_user_function 比较器）。

///|
test "host3_bsearch_comparator" {
  let vm = VitroVM::new()
  for i = 0; i < 5; i = i + 1 {
    guard vm.memory.store_u32(
        vm.mem_map,
        0x7000U + i.reinterpret_as_uint() * 4U,
        (i + 1).reinterpret_as_uint(),
      )
      is Ok(_) else {
      fail("arr")
    }
  }
  guard vm.memory.store_u32(vm.mem_map, 0x7020U, 4U) is Ok(_) else {
    fail("key4")
  }
  guard vm.memory.store_u32(vm.mem_map, 0x7024U, 99U) is Ok(_) else {
    fail("key99")
  }
  // 比较器注册（ip 10：cmp = *key - *elem；const void* 须解引用）
  assert_true(
    vm.register_function(0, @bytecode.FuncMeta::{
      ip: 10,
      arg_count: 2,
      param_count: 2,
      local_count: 8,
      param_sizes: [1, 1],
      return_type: @ast.Type::Int(false, false),
      is_variadic: false,
      local_buffers: [],
    }),
  )
  // **单份 code**：ip 0..9 主流程（两次 bsearch 调用）+ ip 10.. cmp 体
  // （load_program 两次会覆盖 code——call_user_function 的 ip=meta.ip
  // 指向的必须是 cmp 体）
  let code : Array[@opcode.Instruction] = []
  // 第一次：查 4 @0x7020 → 命中 0x700C
  code.push(instr(PushConst, 0))
  code.push(instr(PushConst, 4))
  code.push(instr(PushConst, 5))
  code.push(instr(PushConst, 0x7000))
  code.push(instr(PushConst, 0x7020))
  code.push(instr(CallHost, 81))
  code.push(instr(Ret, 0))
  while code.length() < 10 {
    code.push(instr(Nop, 0))
  }
  // ip 10：cmp 体
  code.push(instr(LoadLocal, 0))
  code.push(instr(LoadMem, 0))
  code.push(instr(LoadLocal, 4))
  code.push(instr(LoadMem, 0))
  code.push(instr(Sub, 0))
  code.push(instr(Ret, 0))
  vm.load_program(code)
  let r = vm.run()
  assert_eq(r, 0x700C)
  assert_eq(vm.error, "")
}

///|
/// 三段锚：printf 全协议（"x=%d!" 单转换符 + 字面量；栈序：参数先压、
/// fmt 后压=栈顶首实参）。
test "host3_printf_protocol" {
  let vm = VitroVM::new()
  let fmt_bytes = @utf8.encode("x=%d!")
  for i = 0; i < fmt_bytes.length(); i = i + 1 {
    guard vm.memory.store_i8(
        vm.mem_map,
        0x6000U + i.reinterpret_as_uint(),
        fmt_bytes[i].to_int(),
      )
      is Ok(_) else {
      fail("fmt")
    }
  }
  guard vm.memory.store_i8(vm.mem_map, 0x6005U, 0) is Ok(_) else { fail("NUL") }
  vm.load_program(
    code_of([
      instr(PushConst, 42), // 实参（先压——C 从右往左）
      instr(PushConst, 0x6000), // fmt（栈顶=首实参）
      instr(CallHost, 15),
    ]),
  )
  let _ = vm.run()
  assert_eq(vm.error, "")
  let outs = vm.output.chunks_of(@host.OutputKind::Stdout)
  assert_eq(outs.length(), 1)
  let text = codes_to_str(outs[0])
  assert_true(
    text.contains("x=42!"),
    msg="输出必须含 x=42!（实得 " + text + "）",
  )
}

///|
/// 三段锚：scanf 全协议（Batch 模式 + %d；成功赋值 1 项、落内存）。
test "host3_scanf_batch_int" {
  let vm = VitroVM::new()
  vm.input = @host.InputState::new([@utf8.encode("42")], true)
  let fmt_bytes = @utf8.encode("%d")
  for i = 0; i < fmt_bytes.length(); i = i + 1 {
    guard vm.memory.store_i8(
        vm.mem_map,
        0x6000U + i.reinterpret_as_uint(),
        fmt_bytes[i].to_int(),
      )
      is Ok(_) else {
      fail("fmt")
    }
  }
  guard vm.memory.store_i8(vm.mem_map, 0x6002U, 0) is Ok(_) else { fail("NUL") }
  vm.load_program(
    code_of([
      instr(PushConst, 0x7000), // ptr（先压）
      instr(PushConst, 0x6000), // fmt（栈顶）
      instr(CallHost, 21),
    ]),
  )
  let r = vm.run()
  assert_eq(r, 1)
  assert_eq(vm.error, "")
  assert_eq(vm.memory.load_u32(vm.mem_map, 0x7000U), Ok(42U))
}

///|
/// 三段锚：getchar Batch 模式 EOF 序列（两字符后 -1 + 粘滞）。
test "host3_getchar_batch_eof" {
  let vm = VitroVM::new()
  vm.input = @host.InputState::new([@utf8.encode("ab")], true)
  let code : Array[@opcode.Instruction] = []
  for k = 0; k < 3; k = k + 1 {
    code.push(instr(CallHost, 33))
  }
  vm.load_program(code)
  let r = vm.run()
  assert_eq(r, -1)
  assert_true(vm.input.eof)
}

///|
/// 三段锚：puts（读串 + 换行 + 返 1）。
test "host3_puts" {
  let vm = VitroVM::new()
  let bytes = @utf8.encode("hi")
  for i = 0; i < bytes.length(); i = i + 1 {
    guard vm.memory.store_i8(
        vm.mem_map,
        0x6000U + i.reinterpret_as_uint(),
        bytes[i].to_int(),
      )
      is Ok(_) else {
      fail("s")
    }
  }
  guard vm.memory.store_i8(vm.mem_map, 0x6002U, 0) is Ok(_) else { fail("NUL") }
  vm.load_program(code_of([instr(PushConst, 0x6000), instr(CallHost, 79)]))
  let r = vm.run()
  assert_eq(r, 1)
  assert_true(
    codes_to_str(vm.output.chunks_of(@host.OutputKind::Stdout)[0]).contains(
      "hi",
    ),
  )
}

///|
/// 三段锚（核心）：call_user_function——比较器用户函数真实执行
/// （cmp(3,1)=2；哨兵帧进 call_stack 后由比较器内 Ret 收尾）。
test "host3_call_user_function" {
  let vm = VitroVM::new()
  assert_true(
    vm.register_function(0, @bytecode.FuncMeta::{
      ip: 10,
      arg_count: 2,
      param_count: 2,
      local_count: 8,
      param_sizes: [1, 1],
      return_type: @ast.Type::Int(false, false),
      is_variadic: false,
      local_buffers: [],
    }),
  )
  assert_true(vm.register_function_name(0, "cmp"))
  let code : Array[@opcode.Instruction] = []
  while code.length() < 10 {
    code.push(instr(Nop, 0))
  }
  code.push(instr(LoadLocal, 0)) // 10: a（字节偏移 0）
  code.push(instr(LoadLocal, 4)) // 11: b（字节偏移 4——LoadLocal operand 是字节偏移）
  code.push(instr(Sub, 0)) // 12: a-b
  code.push(instr(Ret, 0))
  vm.load_program(code)
  let result = vm.call_user_function(0, [3, 1], 100)
  guard result is Some(v) else { fail("比较器必须返回") }
  assert_eq(v, 2)
  // 状态恢复：ip/栈/调用栈全回原态
  assert_eq(vm.ip, 0)
  assert_eq(vm.call_stack.length(), 0)
}

///|
/// 三段锚：qsort 默认比较器（字节序）+ 全协议压序。
test "host3_qsort_default_byte_order" {
  let vm = VitroVM::new()
  guard vm.memory.store_i8(vm.mem_map, 0x7000U, 3) is Ok(_) else { fail("b0") }
  guard vm.memory.store_i8(vm.mem_map, 0x7001U, 1) is Ok(_) else { fail("b1") }
  guard vm.memory.store_i8(vm.mem_map, 0x7002U, 2) is Ok(_) else { fail("b2") }
  vm.load_program(
    code_of([
      instr(PushConst, 0), // compar=0（先压——默认字节比较）
      instr(PushConst, 1), // size=1
      instr(PushConst, 3), // nmemb=3
      instr(PushConst, 0x7000), // base（栈顶）
      instr(CallHost, 52),
    ]),
  )
  let _ = vm.run()
  assert_eq(vm.error, "")
  assert_eq(vm.memory.load_i8(vm.mem_map, 0x7000U), Ok(1))
  assert_eq(vm.memory.load_i8(vm.mem_map, 0x7001U), Ok(2))
  assert_eq(vm.memory.load_i8(vm.mem_map, 0x7002U), Ok(3))
}

///|
/// 三段锚：qsort 比较器路径（int 数组升序——经 call_user_function）。
test "host3_qsort_with_comparator" {
  let vm = VitroVM::new()
  guard vm.memory.store_u32(vm.mem_map, 0x7000U, 3U) is Ok(_) else {
    fail("a0")
  }
  guard vm.memory.store_u32(vm.mem_map, 0x7004U, 1U) is Ok(_) else {
    fail("a1")
  }
  guard vm.memory.store_u32(vm.mem_map, 0x7008U, 2U) is Ok(_) else {
    fail("a2")
  }
  assert_true(
    vm.register_function(0, @bytecode.FuncMeta::{
      ip: 10,
      arg_count: 2,
      param_count: 2,
      local_count: 8,
      param_sizes: [1, 1],
      return_type: @ast.Type::Int(false, false),
      is_variadic: false,
      local_buffers: [],
    }),
  )
  let code : Array[@opcode.Instruction] = []
  while code.length() < 10 {
    code.push(instr(Nop, 0))
  }
  code.push(instr(LoadLocal, 0))
  code.push(instr(LoadLocal, 1))
  code.push(instr(Sub, 0))
  code.push(instr(Ret, 0))
  vm.load_program(code)
  // 压序：compar → size=4 → nmemb=3 → base（栈顶）
  vm.load_program(
    code_of([
      instr(PushConst, 0), // func idx 0（CallHost operand 是 host id——compar 走地址！）
    ]),
  )
  // compar 是函数指针（Call 用的索引形态在内存里也是 idx）——
  // oracle 里 compar = 函数表索引。压 compar=0（func idx 0）
  vm.stack.clear()
  vm.stack.push(0UL) // compar = func idx 0
  vm.stack.push(4UL) // size=4
  vm.stack.push(3UL) // nmemb=3
  vm.stack.push(0x7000UL) // base
  vm.ip = 0
  vm.error = ""
  vm.load_program(code_of([instr(CallHost, 52)]))
  let _ = vm.run()
  assert_eq(vm.error, "")
  assert_eq(vm.memory.load_u32(vm.mem_map, 0x7000U), Ok(1U))
  assert_eq(vm.memory.load_u32(vm.mem_map, 0x7004U), Ok(2U))
  assert_eq(vm.memory.load_u32(vm.mem_map, 0x7008U), Ok(3U))
}

///|
/// 三段锚：bsearch 命中与未命中（默认字节比较——int LE 升序一致）。
test "host3_bsearch_hit_and_miss" {
  let vm = VitroVM::new()
  for i = 0; i < 5; i = i + 1 {
    guard vm.memory.store_u32(
        vm.mem_map,
        0x7000U + i.reinterpret_as_uint() * 4U,
        (i + 1).reinterpret_as_uint(),
      )
      is Ok(_) else {
      fail("arr")
    }
  }
  guard vm.memory.store_u32(vm.mem_map, 0x7020U, 4U) is Ok(_) else {
    fail("key4")
  }
  guard vm.memory.store_u32(vm.mem_map, 0x7024U, 99U) is Ok(_) else {
    fail("key99")
  }
  // 比较器注册（ip 10：cmp = *key - *elem；const void* 须解引用）
  assert_true(
    vm.register_function(0, @bytecode.FuncMeta::{
      ip: 10,
      arg_count: 2,
      param_count: 2,
      local_count: 8,
      param_sizes: [1, 1],
      return_type: @ast.Type::Int(false, false),
      is_variadic: false,
      local_buffers: [],
    }),
  )
  // **单份 code**：ip 0..9 主流程（两次 bsearch 调用）+ ip 10.. cmp 体
  // （load_program 两次会覆盖 code——call_user_function 的 ip=meta.ip
  // 指向的必须是 cmp 体）
  let code : Array[@opcode.Instruction] = []
  // 第一次：查 4 @0x7020 → 命中 0x700C
  code.push(instr(PushConst, 0))
  code.push(instr(PushConst, 4))
  code.push(instr(PushConst, 5))
  code.push(instr(PushConst, 0x7000))
  code.push(instr(PushConst, 0x7020))
  code.push(instr(CallHost, 81))
  code.push(instr(Ret, 0))
  while code.length() < 10 {
    code.push(instr(Nop, 0))
  }
  // ip 10：cmp 体
  code.push(instr(LoadLocal, 0))
  code.push(instr(LoadMem, 0))
  code.push(instr(LoadLocal, 4))
  code.push(instr(LoadMem, 0))
  code.push(instr(Sub, 0))
  code.push(instr(Ret, 0))
  vm.load_program(code)
  let r = vm.run()
  assert_eq(r, 0x700C)
  assert_eq(vm.error, "")
  // 第二次（未命中）：直接换 code 的 key 地址重跑——
  // 主流程改查 99 @0x7024：构造第二份 code（cmp 体 ip 位置不变）
  let code2 : Array[@opcode.Instruction] = []
  code2.push(instr(PushConst, 0))
  code2.push(instr(PushConst, 4))
  code2.push(instr(PushConst, 5))
  code2.push(instr(PushConst, 0x7000))
  code2.push(instr(PushConst, 0x7024))
  code2.push(instr(CallHost, 81))
  code2.push(instr(Ret, 0))
  while code2.length() < 10 {
    code2.push(instr(Nop, 0))
  }
  code2.push(instr(LoadLocal, 0))
  code2.push(instr(LoadMem, 0))
  code2.push(instr(LoadLocal, 4))
  code2.push(instr(LoadMem, 0))
  code2.push(instr(Sub, 0))
  code2.push(instr(Ret, 0))
  vm.load_program(code2)
  vm.ip = 0
  vm.stack.clear()
  vm.error = ""
  let r2 = vm.run()
  assert_eq(r2, 0) // NULL
}

///|
/// 三段锚：U2#13 参数形状教学诊断（qsort 传 8 字节参数比较器 → trap）。
test "host3_qsort_param_shape_diag" {
  let vm = VitroVM::new()
  assert_true(
    vm.register_function(0, @bytecode.FuncMeta::{
      ip: 10,
      arg_count: 2,
      param_count: 2,
      local_count: 16,
      param_sizes: [2, 2], // 8 字节参数——违约形状
      return_type: @ast.Type::Int(false, false),
      is_variadic: false,
      local_buffers: [],
    }),
  )
  let result = vm.call_user_function(0, [0x7000, 0x7004], 100)
  assert_true(result is None)
  assert_true(
    vm.error.contains("比较函数的参数必须是 4 字节指针"),
  )
}

///|
/// 三段锚：STEP（current_line 更新）+ guards 死面直通。
test "host3_step_and_guards" {
  let vm = VitroVM::new()
  vm.load_program(
    code_of([
      instr(PushConst, 77),
      instr(CallHost, 1), // STEP
      instr(PushConst, 0x5000),
      instr(CallHost, 131), // set_array_guard（死面直通）
      instr(CallHost, 132), // clear_array_guard
    ]),
  )
  let _ = vm.run()
  assert_eq(vm.current_line, 77)
  assert_eq(vm.error, "")
}

///|
/// 六轮审阅 P2 锚：bsearch 野指针 key（U2#13——key+size 越界按未找到
/// 返回 NULL，不进比较器；且早退不减深度）。
test "host3_bsearch_wild_key_null" {
  let vm = VitroVM::new()
  for i = 0; i < 5; i = i + 1 {
    guard vm.memory.store_u32(
        vm.mem_map,
        0x7000U + i.reinterpret_as_uint() * 4U,
        (i + 1).reinterpret_as_uint(),
      )
      is Ok(_) else {
      fail("arr")
    }
  }
  // key = 0xFFFFF0（+4 越过 MEM_SIZE）——野指针
  vm.load_program(
    code_of([
      instr(PushConst, 0), // compar
      instr(PushConst, 4),
      instr(PushConst, 5),
      instr(PushConst, 0x7000),
      instr(PushConst, 0xFFFFF0),
      instr(CallHost, 81),
    ]),
  )
  let r = vm.run()
  assert_eq(r, 0) // NULL（不 trap、不进比较器）
  assert_eq(vm.error, "")
  assert_eq(vm.qsort_depth, 0) // 早退不减深度——计数器未被污染
}

///|
/// 六轮审阅 P2 锚：bsearch 默认字节比较分支（compar=0 不查函数表——
/// 未注册任何函数时字节比较命中）。
test "host3_bsearch_default_branch" {
  let vm = VitroVM::new()
  for i = 0; i < 5; i = i + 1 {
    guard vm.memory.store_u32(
        vm.mem_map,
        0x7000U + i.reinterpret_as_uint() * 4U,
        (i + 1).reinterpret_as_uint(),
      )
      is Ok(_) else {
      fail("arr")
    }
  }
  guard vm.memory.store_u32(vm.mem_map, 0x7020U, 3U) is Ok(_) else {
    fail("key3")
  }
  vm.load_program(
    code_of([
      instr(PushConst, 0), // compar=0 → 默认字节比较（未注册函数也工作）
      instr(PushConst, 4),
      instr(PushConst, 5),
      instr(PushConst, 0x7000),
      instr(PushConst, 0x7020),
      instr(CallHost, 81),
    ]),
  )
  let r = vm.run()
  assert_eq(r, 0x7008) // 3 在 idx2 → base+8
  assert_eq(vm.error, "")
}

///|
/// 六轮审阅 P2 锚：qsort/bsearch 深度限 8（共用计数器——8 层后 note+NULL）。
test "host3_depth_limit_8" {
  let vm = VitroVM::new()
  vm.qsort_depth = 8 // 直接置满
  guard vm.memory.store_u32(vm.mem_map, 0x7020U, 4U) is Ok(_) else {
    fail("key")
  }
  vm.load_program(
    code_of([
      instr(PushConst, 0),
      instr(PushConst, 4),
      instr(PushConst, 5),
      instr(PushConst, 0x7000),
      instr(PushConst, 0x7020),
      instr(CallHost, 81), // bsearch @深度 8 → note + NULL
    ]),
  )
  let r = vm.run()
  assert_eq(r, 0)
  assert_true(vm.output.chunks_of(@host.OutputKind::Note).length() >= 1)
  vm.qsort_depth = 8
  vm.stack.clear()
  vm.ip = 0
  vm.error = ""
  vm.load_program(
    code_of([
      instr(PushConst, 0),
      instr(PushConst, 1),
      instr(PushConst, 2),
      instr(PushConst, 0x7000),
      instr(CallHost, 52), // qsort @深度 8 → note + no-op
    ]),
  )
  let _ = vm.run()
  assert_true(vm.output.chunks_of(@host.OutputKind::Note).length() >= 2)
}
