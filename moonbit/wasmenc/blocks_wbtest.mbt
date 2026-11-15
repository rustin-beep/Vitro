// blocks_wbtest —— 批 4a 块划分器 + 出口高度锚（J9：越界/下溢/
// CallPtr 三路证红；短路留值合法化锚——批 4a 架构修正面）。

///|
fn b4_ctx() -> EmitCtx {
  {
    f64_constants: [1.5, -0.25],
    i64_constants: [42L, -1L],
    argc: 3,
    argv_addr: 0x4000,
    fallthrough_pc: 77,
    host_argv_ptr: 0x5000,
    symbol_sizes: [4, 10],
  }
}

///|
/// 绿基线：直线块 + 条件跳转双分支——leader/块数/出口高度全绿。
/// 程序形态（gip 语义；条件值须与 JumpIf 同块先压——codegen 求值序）：
///   0 StepEvent(1) / 1 PushConst(1) / 2 StoreLocal(0)   ← 块 0（0..2）
///   3 PushConst(0) / 4 JumpIfZero(8)                    ← 块 1（条件求值 + 出口）
///   5 PushConst(2) / 6 StoreLocal(0) / 7 Jump(0)        ← 块 2（taken 体 + 回边）
///   8 PushConst(0) / 9 Ret(0)                           ← 块 3（出口：Ret 前压返回值）
test "blocks_partition_and_exit_heights_green" {
  let ops : Array[@opcode.OpCode] = [
    StepEvent,
    PushConst,
    StoreLocal, // 0..2
    PushConst,
    JumpIfZero, // 3..4
    PushConst,
    StoreLocal,
    Jump, // 5..7
    PushConst,
    Ret, // 8..9
  ]
  let operands : Array[Int32] = [1, 1, 0, 0, 8, 2, 0, 0, 0, 0]
  let bt = partition_blocks(ops, operands, [8], 0)
  guard bt is Ok(b) else { fail("划分须绿") }
  // leader：入口 0 / JumpIf 目标 8 / 控制流后继 5、8（Jump@7 后继 8 已在）
  assert_eq(b.starts, [0, 5, 8], msg="leader 集合")
  // 出口高度（本程序无短路留值——四块出口恒 0）
  let r = blocks_exit_heights(ops, operands, b, fn(_g) { 0 }, b4_ctx())
  guard r is Ok(hs) else { fail("出口高度须绿") }
  assert_eq(hs.length(), 3, msg="三块（starts [0,5,8]）")
  assert_eq(hs[0], 0, msg="块 0 出口")
  assert_eq(hs[1], 0, msg="块 1 出口")
  assert_eq(hs[2], 0, msg="块 2 出口")
}

///|
/// 短路留值合法化锚（批 4a 架构修正）：Dup+JumpIfZero 落空后留 1 值
/// 跨块——出口高 1 **合法**（jit PoC「块边界栈空」假设的放宽面；libc
/// 真实字节码实锤形态——gip6/7 同构片段）。
test "blocks_exit_height_shortcircuit_legal" {
  let ops : Array[@opcode.OpCode] = [
    LoadLocal,
    PushConst,
    Ge,
    Dup,
    JumpIfZero, // 0..4（目标 5）
    PushConst,
    Ret, // 5..6
  ]
  let operands : Array[Int32] = [0, 48, 0, 0, 5, 0, 0]
  let bt = partition_blocks(ops, operands, [], 0)
  guard bt is Ok(b) else { fail("划分须绿") }
  let r = blocks_exit_heights(ops, operands, b, fn(_g) { 0 }, b4_ctx())
  guard r is Ok(hs) else { fail("出口高度须绿——Dup 留值合法") }
  // 块 0 = [0,5)：+1+1-1+1-1（JumpIf 弹判）= 出口高 1（Dup 留值）
  assert_eq(hs[0], 1, msg="块 0 出口高 1（短路留值）")
}

///|
/// J9 一：Jump 目标越界 → BadTarget 红（组序列与元数据不符 fail loud）。
test "blocks_bad_target_red" {
  let ops : Array[@opcode.OpCode] = [PushConst, Jump]
  let operands : Array[Int32] = [0, 99]
  let r = partition_blocks(ops, operands, [], 0)
  assert_true(r is Err(BadTarget(99, 2)), msg="Jump 目标越界必红")
}

///|
/// J9 二：块内下溢（高度 < 0）→ ExitStackNonEmpty 红（出口非零已随
/// 短路留值合法化——下溢仍是不可执行形态）。
test "blocks_underflow_red" {
  // StoreLocal 开块（空栈弹 1 → -1）
  let ops : Array[@opcode.OpCode] = [StoreLocal, PushConst, Ret]
  let operands : Array[Int32] = [0, 0, 0]
  let bt = partition_blocks(ops, operands, [], 0)
  guard bt is Ok(b) else { fail("划分须绿") }
  // 入口高全 0（单块程序）——下溢走联立判定
  let r = blocks_underflow_with_entry(
    ops,
    operands,
    b,
    [0],
    fn(_g) { 0 },
    b4_ctx(),
  )
  assert_true(r is Err(ExitStackNonEmpty(_, _, _)), msg="块内下溢必红")
}

///|
/// J9 三：CallPtr → CallPtrUnsupported 红（首版禁译面 fail loud——运行期
/// func meta 查表的搬运序列无法静态展开，归 4b 闸禁译登记）。
test "blocks_callptr_unsupported_red" {
  let ops : Array[@opcode.OpCode] = [CallPtr]
  let operands : Array[Int32] = [0]
  let r = partition_blocks(ops, operands, [], 0)
  assert_true(r is Err(CallPtrUnsupported(0)), msg="CallPtr 首版禁译必红")
}

///|
/// Call 参数消费计数（control_pop_words + call_arg_words 供给面）：
/// void 调用形态（无返回值消费——返回值走 G_RV 通道）。
test "blocks_call_arg_words_accounting" {
  // void 调用：Call 后继块直接 RetVoid（无返回值消费）
  let ops : Array[@opcode.OpCode] = [PushConst, PushConst, Call, RetVoid]
  let operands : Array[Int32] = [1, 2, 3, 0]
  let bt = partition_blocks(ops, operands, [3], 0)
  guard bt is Ok(b) else { fail("划分须绿") }
  // Call@2 的参数 word 数 = 2（两个 i32 实参）——出口高 0
  let r = blocks_exit_heights(ops, operands, b, fn(_g) { 2 }, b4_ctx())
  guard r is Ok(hs) else { fail("参数消费计数须绿") }
  assert_eq(hs[0], 0, msg="块 0 出口高 0（参数弹尽）")
  // 负例：同序列按 0 word 计 → 出口高 2（漏计——组装器 spill 深度
  // 错配的源头形态，口径非平凡自证；出口非零本身合法）
  let r2 = blocks_exit_heights(ops, operands, b, fn(_g) { 0 }, b4_ctx())
  guard r2 is Ok(hs2) else { fail("负例须绿（出口高任意合法）") }
  assert_eq(hs2[0], 2, msg="漏计参数 word 出口高 2")
}
