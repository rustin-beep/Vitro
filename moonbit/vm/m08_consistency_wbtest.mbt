///|
/// #482 折叠↔运行期一致性闸·双上下文直拍锚（2026-11-05，方案 A）——
/// m08_fold_wbtest（typeck）的传递性形态补洞：那侧锚断言「折叠值 == clang
/// 四端真值」，运行期不进锚，凭「真值 == 运行期值」传递性成立——VM 臂内
/// opcode→(op,dom) 映射错、栈原语形态错等**核外运行期漂移**在锚面失守
/// （该面此前仅由 vm_diff golden / fuzz / clang_direct 语料防线兜，属锚
/// 密度缺口）。本文件把运行期侧拉进锚：每条表达式族「VM 真跑值 vs 折叠
/// 求值核直调值」两侧各求值一次直接同值断言（折叠上下文 = @arith 核直调
/// ——typeck/const_eval 折叠器接核后的同一求值入口，批 1 起 typeck 侧
/// 折叠值即核产出；运行期上下文 = VitroVM 直驱 codegen 对该表达式族的
/// opcode 发射形态，vm_exec_wbtest 同款最轻形态，零 spawn）。
///
/// 失效面判别（#482 失效面表的两类漂移）：
/// - 核内语义错 → 折叠值先错（typeck 锚红 + 本锚核侧同红）；
/// - **核外运行期错**（如 DivQ 误映 U64 域）→ 核值仍对、VM 值错 →
///   **本锚红**（J9 杀阵实录：改坏 exec_float.mbt DivQ 臂 I64→U64 →
///   m08c_g1 红；改坏 ShrQ 臂 I64→U64 → m08c_g3 独 红——既有
///   vm_exec_wbtest 无 ShrQ 值锚，独红面即本批补的缺口）。
///
/// clang 真值口径同 typeck/m08_fold_wbtest：Win clang 22.1.4 / Win gcc /
/// WSL gcc 15.2 / WSL clang 21.1.8 四端一致（M08 §3.1/§3.3）——每条锚第
/// 三重断言对真值字面量，防「两侧一起错」的同漂移盲区。
///
/// i32 溢出面**刻意分叉**（设计单 §五·2 分划契约，不翻案）：静态折叠照折
/// 回绕值带 W3090（对齐 clang 静态折值），运行期 i32 族教学 trap——
/// m08c_int_max_plus1_split_contract 锁「分叉是刻意的」三态契约。

///|
fn m08c_instr(op : @opcode.OpCode, operand : Int32) -> @opcode.Instruction {
  @opcode.Instruction::new(op, operand, @source.SourceLoc::new(1, 1))
}

///|
/// g1：`long long g1 = -1LL / 2u;` → 0（公共类型 signed LL）。
/// 运行期形态：DivQ（I64 域）——域随左操作数，批 5 对拍锚
/// parity_div_ll_uint_emits_divq 同款发射。
test "m08c_g1_ll_vs_uint_div" {
  let vm = VitroVM::new()
  vm.set_i64_constants([-1L, 2L])
  vm.load_program([
    m08c_instr(PushConstQ, 0),
    m08c_instr(PushConstQ, 1),
    m08c_instr(DivQ, 0),
  ])
  let _ = vm.run()
  let vm_val = vm.stack[vm.stack.length() - 1].reinterpret_as_int64()
  let folded = @arith.eval_int_binary(@arith.OpDiv, -1L, 2L, @arith.I64)
  assert_eq(
    vm_val,
    0L,
    msg="VM 真跑 -1LL/2u 应得 0（clang 四端真值）",
  )
  assert_eq(folded, Ok(0L), msg="核折叠求值同值（双上下文直拍）")
  assert_eq(
    folded,
    Ok(vm_val),
    msg="上下文 1（折叠）与上下文 2（VM 真跑）必须同值",
  )
}

///|
/// g2：`int g2 = (unsigned char)200 / -1;` → -200（uchar 先提升 signed int）。
/// 运行期形态：TruncUByte（uchar 窄化）后 Div（I32 有符号域）。
test "m08c_g2_uchar_promote_div" {
  let vm = VitroVM::new()
  vm.load_program([
    m08c_instr(PushConst, 200),
    m08c_instr(TruncUByte, 0),
    m08c_instr(PushConst, -1),
    m08c_instr(Div, 0),
  ])
  let _ = vm.run()
  let vm_val = vm.stack[vm.stack.length() - 1].reinterpret_as_int64()
  let folded = @arith.eval_int_binary(@arith.OpDiv, 200L, -1L, @arith.I32)
  assert_eq(vm_val, -200L, msg="VM 真跑 (uchar)200/-1 应得 -200")
  assert_eq(folded, Ok(-200L), msg="核折叠求值同值")
  assert_eq(folded, Ok(vm_val), msg="双上下文同值")
}

///|
/// g3：`long long g3 = -1LL >> 1u;` → -1（Shr 域随左操作数 LL，算术右移；
/// 误映无符号域则逻辑右移得 9223372036854775807）。
/// 运行期形态：ShrQ（I64 域）——既有 vm_exec_wbtest 无 ShrQ 值锚，本条
/// 是「核外运行期漂移独红面」（J9 杀阵 B 实录）。
test "m08c_g3_ll_shr_uint" {
  let vm = VitroVM::new()
  vm.set_i64_constants([-1L, 1L])
  vm.load_program([
    m08c_instr(PushConstQ, 0),
    m08c_instr(PushConstQ, 1),
    m08c_instr(ShrQ, 0),
  ])
  let _ = vm.run()
  let vm_val = vm.stack[vm.stack.length() - 1].reinterpret_as_int64()
  let folded = @arith.eval_int_binary(@arith.OpShr, -1L, 1L, @arith.I64)
  assert_eq(vm_val, -1L, msg="VM 真跑 -1LL>>1u 应得 -1（算术右移）")
  assert_eq(folded, Ok(-1L), msg="核折叠求值同值")
  assert_eq(folded, Ok(vm_val), msg="双上下文同值")
}

///|
/// g4 变体（比较域）：`-1LL < 1ULL` → 0（ULL 域 2^64-1；I64 误判 -1<1=1）
/// 与 `2^64-1 > 1ULL` → 1 成对——A2 病（Eq 忽略 unsigned 域）的运行期
/// 对偶面。运行期形态：ULtQ/UGtQ（U64 域）。
test "m08c_g4_ull_cmp_domain" {
  let vm = VitroVM::new()
  vm.set_i64_constants([-1L, 1L])
  vm.load_program([
    m08c_instr(PushConstQ, 0),
    m08c_instr(PushConstQ, 1),
    m08c_instr(ULtQ, 0),
    m08c_instr(PushConstQ, 0),
    m08c_instr(PushConstQ, 1),
    m08c_instr(UGtQ, 0),
  ])
  let _ = vm.run()
  let vm_lt = vm.stack[vm.stack.length() - 2].to_int()
  let vm_gt = vm.stack[vm.stack.length() - 1].to_int()
  let f_lt = @arith.eval_int_binary(@arith.OpLt, -1L, 1L, @arith.U64)
  let f_gt = @arith.eval_int_binary(@arith.OpGt, -1L, 1L, @arith.U64)
  assert_eq(vm_lt, 0, msg="VM 真跑 -1LL<1ULL 应得 0（U64 域 2^64-1）")
  assert_eq(f_lt, Ok(0L), msg="核折叠求值同值")
  assert_eq(f_lt, Ok(vm_lt.to_int64()), msg="双上下文同值")
  assert_eq(vm_gt, 1, msg="VM 真跑 2^64-1>1ULL 应得 1")
  assert_eq(f_gt, Ok(1L), msg="核折叠求值同值")
  assert_eq(f_gt, Ok(vm_gt.to_int64()), msg="双上下文同值")
}

///|
/// A5：`int f1 = (int)1e300;` → 2147483647 饱和（超界饱和不回绕——M08
/// §3.1 #3；1e10 同格见 typeck 锚，本条取更极端的 1e300 同饱和格）。
/// 运行期形态：CastD2I（VM 执行器侧饱和）；折叠侧 = f2i_saturate_i32
/// （typeck 折叠器同款核出口）。1e300 用循环乘 10 构造（陷阱 #13：e 记法
/// 浮点字面量不可用——定点写不下，循环构造；累积舍入不影响饱和格判定的
/// 双侧同输入）。
test "m08c_f2i_saturate_1e300" {
  let mut big : Double = 1.0
  for _i in 0..<300 {
    big = big * 10.0
  }
  let vm = VitroVM::new()
  vm.stack.push(big.reinterpret_as_uint64())
  vm.load_program([m08c_instr(CastD2I, 0)])
  let _ = vm.run()
  let vm_val = vm.stack[vm.stack.length() - 1].reinterpret_as_int64()
  let folded = @arith.f2i_saturate_i32(big)
  assert_eq(vm_val, 2147483647L, msg="VM 真跑 (int)1e300 应饱和 INT_MAX")
  assert_eq(folded, 2147483647L, msg="核饱和出口同值")
  assert_eq(vm_val, folded, msg="双上下文同值")
}

///|
/// LLONG_MAX+1 → LLONG_MIN（I64 域回绕，VM 不 trap——与 i32 族教学 trap
/// 分口径；typeck 折叠侧折同一回绕值，p3_i64_overflow_warns 锚已锁
/// W3090 + 值）。运行期形态：AddQ（I64 回绕）。
test "m08c_llong_max_plus1_wrap" {
  let vm = VitroVM::new()
  vm.set_i64_constants([9223372036854775807L, 1L])
  vm.load_program([
    m08c_instr(PushConstQ, 0),
    m08c_instr(PushConstQ, 1),
    m08c_instr(AddQ, 0),
  ])
  let _ = vm.run()
  let vm_val = vm.stack[vm.stack.length() - 1].reinterpret_as_int64()
  let folded = @arith.eval_int_binary(
    @arith.OpAdd,
    9223372036854775807L,
    1L,
    @arith.I64,
  )
  assert_eq(
    vm_val,
    -9223372036854775808L,
    msg="VM 真跑 LLONG_MAX+1 回绕 LLONG_MIN",
  )
  assert_eq(
    folded,
    Ok(-9223372036854775808L),
    msg="核折叠求值同值（I64 无故障面）",
  )
  assert_eq(folded, Ok(vm_val), msg="双上下文同值")
}

///|
/// 移位边界（M08 §3.3）：`1LL << 62` 合法格 → 2^62；`1LL << 64` 越界格
/// 双侧故障面一致（VM 教学文案 trap「Shl 移位量越界：64」/ 核
/// Err(ShiftOutOfRange(64))——值面与故障面都对拍）。运行期形态：ShlQ
///（U64 域位模式左移，与符号无关）。
test "m08c_shl_boundary_62_and_64" {
  // 合法格：1LL << 62 = 2^62
  let vm = VitroVM::new()
  vm.set_i64_constants([1L, 62L])
  vm.load_program([
    m08c_instr(PushConstQ, 0),
    m08c_instr(PushConstQ, 1),
    m08c_instr(ShlQ, 0),
  ])
  let _ = vm.run()
  let vm_val = vm.stack[vm.stack.length() - 1].reinterpret_as_int64()
  let folded = @arith.eval_int_binary(@arith.OpShl, 1L, 62L, @arith.U64)
  assert_eq(vm_val, 4611686018427387904L, msg="VM 真跑 1LL<<62 应得 2^62")
  assert_eq(folded, Ok(4611686018427387904L), msg="核折叠求值同值")
  assert_eq(folded, Ok(vm_val), msg="双上下文同值")
  // 越界格：1LL << 64 —— 双侧故障面
  let vm2 = VitroVM::new()
  vm2.set_i64_constants([1L, 64L])
  vm2.load_program([
    m08c_instr(PushConstQ, 0),
    m08c_instr(PushConstQ, 1),
    m08c_instr(ShlQ, 0),
  ])
  ignore(vm2.step())
  ignore(vm2.step())
  let r = vm2.step()
  assert_true(r is Trap, msg="VM 真跑 1LL<<64 应 trap（移位量越界）")
  assert_true(
    vm2.error.contains("Shl 移位量越界"),
    msg="trap 文案须为移位量越界",
  )
  let folded2 = @arith.eval_int_binary(@arith.OpShl, 1L, 64L, @arith.U64)
  assert_eq(
    folded2,
    Err(@arith.ShiftOutOfRange(64L)),
    msg="核求值同故障面（ShiftOutOfRange(64)）",
  )
}

///|
/// DivQ 故障面（g5 族的运行期对偶）：`LLONG_MIN / -1` 与 `x / 0` 双侧
/// 故障一致；合法格 `-7 / 2` 值面同值（DivC 负商符号扩展既有锚
/// exec_div_mod_negative_sign_extension 同值口径）。
test "m08c_divq_fault_domain" {
  // 合法格：-7LL / 2 = -3
  let vm = VitroVM::new()
  vm.set_i64_constants([-7L, 2L])
  vm.load_program([
    m08c_instr(PushConstQ, 0),
    m08c_instr(PushConstQ, 1),
    m08c_instr(DivQ, 0),
  ])
  let _ = vm.run()
  let vm_val = vm.stack[vm.stack.length() - 1].reinterpret_as_int64()
  let folded = @arith.eval_int_binary(@arith.OpDiv, -7L, 2L, @arith.I64)
  assert_eq(vm_val, -3L, msg="VM 真跑 -7LL/2 应得 -3")
  assert_eq(folded, Ok(-3L), msg="核折叠求值同值")
  assert_eq(folded, Ok(vm_val), msg="双上下文同值")
  // 故障格 1：LLONG_MIN / -1 → 双侧溢出故障
  let vm2 = VitroVM::new()
  vm2.stack.push((-9223372036854775808L).reinterpret_as_uint64())
  vm2.stack.push((-1L).reinterpret_as_uint64())
  vm2.load_program([m08c_instr(DivQ, 0)])
  let r = vm2.step()
  assert_true(r is Trap, msg="VM 真跑 LLONG_MIN/-1 应 trap")
  assert_true(vm2.error.contains("long long 除法溢出"))
  let folded2 = @arith.eval_int_binary(
    @arith.OpDiv,
    -9223372036854775808L,
    -1L,
    @arith.I64,
  )
  assert_eq(
    folded2,
    Err(@arith.DivOverflow),
    msg="核求值同故障面（DivOverflow）",
  )
  // 故障格 2：除零 → 双侧 DivByZero
  let vm3 = VitroVM::new()
  vm3.stack.push(10L.reinterpret_as_uint64())
  vm3.stack.push(0L.reinterpret_as_uint64())
  vm3.load_program([m08c_instr(DivQ, 0)])
  let r3 = vm3.step()
  assert_true(r3 is Trap, msg="VM 真跑 10/0 应 trap")
  assert_eq(vm3.trap_code, "E3088", msg="结构化码随文案")
  let folded3 = @arith.eval_int_binary(@arith.OpDiv, 10L, 0L, @arith.I64)
  assert_eq(
    folded3,
    Err(@arith.DivByZero),
    msg="核求值同故障面（DivByZero）",
  )
}

///|
/// UDivQ 值面（g4 同族）：`(2^64-1)ULL / 3` → 6148914691236517205
/// （位模式重解释做无符号除——误映 I64 域则 -1/3=0）。
test "m08c_udivq_unsigned_domain" {
  let vm = VitroVM::new()
  vm.set_i64_constants([-1L, 3L])
  vm.load_program([
    m08c_instr(PushConstQ, 0),
    m08c_instr(PushConstQ, 1),
    m08c_instr(UDivQ, 0),
  ])
  let _ = vm.run()
  let vm_val = vm.stack[vm.stack.length() - 1].reinterpret_as_int64()
  let folded = @arith.eval_int_binary(@arith.OpDiv, -1L, 3L, @arith.U64)
  assert_eq(
    vm_val,
    6148914691236517205L,
    msg="VM 真跑 (2^64-1)ULL/3 应得 6148914691236517205",
  )
  assert_eq(folded, Ok(6148914691236517205L), msg="核折叠求值同值")
  assert_eq(folded, Ok(vm_val), msg="双上下文同值")
}

///|
/// **i32 溢出分划契约锚**（设计单 §五·2 不翻案的锚形态）：`INT_MAX + 1`
/// 三态——静态折叠照折回绕 -2147483648 带 W3090（typeck 锚
/// m08_s2_int_add_overflow_warns 已锁，对齐 clang 静态折值）；核 I32 域
/// 求值 Err(AddOverflow)（const_eval 消费侧「W 级照折」的故障输入）；VM
/// 运行期教学 trap（exec_add_overflow_traps 已锁逐字文案）。本锚锁「两侧
/// **刻意分叉**」：VM Trap + 核 Err——未来若有人想统一 i32 口径（trap 改
/// 回绕或折叠改拒折），撞本锚须先翻 §五·2 裁定，不许静默改。
test "m08c_int_max_plus1_split_contract" {
  // 运行期：教学 trap（不改值、不回绕）
  let vm = VitroVM::new()
  vm.load_program([
    m08c_instr(PushConst, 2147483647),
    m08c_instr(PushConst, 1),
    m08c_instr(Add, 0),
  ])
  ignore(vm.step())
  ignore(vm.step())
  let r = vm.step()
  assert_true(
    r is Trap,
    msg="VM 运行期 INT_MAX+1 必须 trap（教学口径）",
  )
  // 核：I32 域溢出产故障（const_eval 消费侧照折回绕——折叠侧值锚在 typeck）
  let folded = @arith.eval_int_binary(@arith.OpAdd, 2147483647L, 1L, @arith.I32)
  assert_eq(
    folded,
    Err(@arith.AddOverflow),
    msg="核 I32 域溢出必须产 AddOverflow 故障",
  )
}
