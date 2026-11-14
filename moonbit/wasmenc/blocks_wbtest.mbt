// blocks_wbtest —— 批 4a 块划分器 + 出口栈空闸锚（J9：越界/栈非空/
// CallPtr 三路证红——「PoC 假设升格为机检」的防线自证）。

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
/// 绿基线：直线块 + 条件跳转双分支——leader/块数/栈空全绿。
/// 程序形态（gip 语义；条件值须与 JumpIf 同块先压——codegen 求值序）：
///   0 StepEvent(1) / 1 PushConst(1) / 2 StoreLocal(0)   ← 块 0（0..2）
///   3 PushConst(0) / 4 JumpIfZero(8)                    ← 块 1（条件求值 + 出口）
///   5 PushConst(2) / 6 StoreLocal(0) / 7 Jump(0)        ← 块 2（taken 体 + 回边）
///   8 PushConst(0) / 9 Ret(0)                           ← 块 3（出口：Ret 前压返回值）
test "blocks_partition_and_exit_stacks_green" {
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
  // 出口栈空（块 0：StoreLocal 归零 ✓；块 1：JumpIf 消费条件 ✓；
  // 块 2：Jump 前归零 ✓；块 3：PushConst+Ret 归零 ✓）
  let r = blocks_exit_stacks_empty(ops, operands, b, fn(_g) { 0 }, b4_ctx())
  assert_true(r is Ok(_), msg="栈空闸须绿")
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
/// J9 二：块出口栈非空 → ExitStackNonEmpty 红——PoC translate.mjs:127
/// 人工 throw 的机检升格（块尾残留 = dispatch 直落拼接破坏栈平衡——
/// 该程序进禁译面，不静默）。
test "blocks_exit_stack_nonempty_red" {
  // PushConst 后直接块边界（Jump@1 后继成新块、PushConst 残留 1 项）
  let ops : Array[@opcode.OpCode] = [PushConst, PushConst, Jump]
  let operands : Array[Int32] = [1, 2, 0]
  let bt = partition_blocks(ops, operands, [], 0)
  guard bt is Ok(b) else { fail("划分须绿") }
  let r = blocks_exit_stacks_empty(ops, operands, b, fn(_g) { 0 }, b4_ctx())
  assert_true(r is Err(ExitStackNonEmpty(_, _, _)), msg="出口栈非空必红")
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
/// **void 调用形态**（无返回值消费——返回值路径走 G_RV 通道：Ret 存
/// G_RV、返回点块开头 load 回 wasm 栈，块边界栈空由该约定保持——见
/// blocks.mbt 头注「返回值通道」；返回值正路径的指令流验证随
/// dispatchloop 组装器锚）。块 0 以 [PushConst;PushConst;Call] 验证
/// word 口径（2 word 参数被消费）。
test "blocks_call_arg_words_accounting" {
  // void 调用：Call 后继块直接 Ret（无返回值消费）
  let ops : Array[@opcode.OpCode] = [PushConst, PushConst, Call, RetVoid]
  let operands : Array[Int32] = [1, 2, 3, 0]
  let bt = partition_blocks(ops, operands, [3], 0)
  guard bt is Ok(b) else { fail("划分须绿") }
  // Call@2 的参数 word 数 = 2（两个 i32 实参）
  let r = blocks_exit_stacks_empty(ops, operands, b, fn(_g) { 2 }, b4_ctx())
  assert_true(r is Ok(_), msg="参数消费计数须绿")
  // 负例：同序列按 0 word 计 → 块尾残留 2 → 红（口径非平凡自证）
  let r2 = blocks_exit_stacks_empty(ops, operands, b, fn(_g) { 0 }, b4_ctx())
  assert_true(
    r2 is Err(ExitStackNonEmpty(_, _, _)),
    msg="漏计参数 word 必红",
  )
}
