///|
/// bytecode 结构验证器 J9 埋雷（#200 P0）——先证红再采信绿：每类不变量
/// 各注入一例违约，验证器必须报对应 kind；干净夹具必须零违约。
/// 红锚形态：kind 字符串断言（不是计数——计数漂移不定位）。

///|
/// 最小干净夹具：`int main(void) { return 42; }` 的等价产物。
/// code：[0]Jump 3 / [1]PushConst 42 / [2]Ret（main 段 [1,3)）/
/// [3]Call 1089 / [4]Ret（wrapper 段）。
fn mk_clean_output() -> CompileOutput {
  let loc = @source.SourceLoc::new(1, 1)
  {
    code: [
      @opcode.Instruction::new(Jump, 3, loc),
      @opcode.Instruction::new(PushConst, 42, loc),
      @opcode.Instruction::new(Ret, 0, loc),
      @opcode.Instruction::new(Call, 1089, loc),
      @opcode.Instruction::new(Ret, 0, loc),
    ],
    globals_init_32: [],
    globals_init_64: [],
    func_table: {
      "main": {
        ip: 1,
        arg_count: 0,
        param_count: 0,
        local_count: 0,
        param_sizes: [],
        return_type: @ast.Type::int(),
        is_variadic: false,
        local_buffers: [],
      },
    },
    func_index: { "main": 1089 },
    string_data: [],
    source_map: [],
    symbols: [],
    struct_defs: {},
    union_defs: {},
    f64_constants: [],
    i64_constants: [],
    global_data_end: GLOBAL_START,
  }
}

///|
/// 夹具改写器：main 段体替换为 inss（自动维持段结构——Jump wrapper /
/// 函数 ip=1 / wrapper 段不动）。
fn with_main_body(
  o : CompileOutput,
  inss : Array[@opcode.Instruction],
) -> CompileOutput {
  let loc = @source.SourceLoc::new(1, 1)
  let code : Array[@opcode.Instruction] = [
    @opcode.Instruction::new(Jump, 1 + inss.length(), loc),
  ]
  for ins in inss {
    code.push(ins)
  }
  code.push(@opcode.Instruction::new(Call, 1089, loc))
  code.push(@opcode.Instruction::new(Ret, 0, loc))
  { ..o, code, }
}

///|
/// 断言违约清单包含指定 kind（含 detail 片段）。
fn expect_violation(
  vs : Array[VerifyViolation],
  kind : String,
  detail_part : String,
) -> Unit raise {
  for x in vs {
    if x.kind == kind && x.detail.contains(detail_part) {
      return
    }
  }
  fail(
    "期望违约 kind=\{kind} detail~\"\{detail_part}\" 未命中；实得 \{vs.length()} 条：\n\{verify_violations_json(vs)}",
  )
}

///|
test "verify: 干净夹具零违约" {
  let vs = verify_compile_output(mk_clean_output(), false)
  assert_eq(
    vs.length(),
    0,
    msg="干净夹具必须零违约，实得：\{verify_violations_json(vs)}",
  )
}

///|
test "verify: 栈下溢（Pop 空栈）" {
  let loc = @source.SourceLoc::new(1, 1)
  let o = with_main_body(mk_clean_output(), [
    @opcode.Instruction::new(Pop, 0, loc),
    @opcode.Instruction::new(PushConst, 0, loc),
    @opcode.Instruction::new(Ret, 0, loc),
  ])
  expect_violation(
    verify_compile_output(o, false),
    "stack-underflow",
    "Pop 弹 1 word 但栈深仅 0",
  )
}

///|
test "verify: Ret 守恒破坏（返回前栈深 2）" {
  let loc = @source.SourceLoc::new(1, 1)
  let o = with_main_body(mk_clean_output(), [
    @opcode.Instruction::new(PushConst, 1, loc),
    @opcode.Instruction::new(PushConst, 2, loc),
    @opcode.Instruction::new(Ret, 0, loc),
  ])
  expect_violation(
    verify_compile_output(o, false),
    "stack-unbalanced-ret",
    "Ret 前栈深 2 ≠ 1",
  )
}

///|
test "verify: RetVoid 守恒破坏（残留 1）" {
  let loc = @source.SourceLoc::new(1, 1)
  let o = mk_clean_output()
  // main 体：压 1 后 RetVoid——残留深 1
  let o = with_main_body(o, [
    @opcode.Instruction::new(PushConst, 7, loc),
    @opcode.Instruction::new(RetVoid, 0, loc),
  ])
  expect_violation(
    verify_compile_output(o, false),
    "stack-unbalanced-ret",
    "RetVoid 前栈深 1 ≠ 0",
  )
}

///|
test "verify: 跳转汇合点栈深分叉" {
  let loc = @source.SourceLoc::new(1, 1)
  // [1]PushConst（深1）/[2]JumpIfZero 5（弹后深0，记录 target5:0）/
  // [3]PushConst（深1）/[4]Jump 5（记录 target5:1——冲突）/[5]Ret
  let o = with_main_body(mk_clean_output(), [
    @opcode.Instruction::new(PushConst, 0, loc),
    @opcode.Instruction::new(JumpIfZero, 5, loc),
    @opcode.Instruction::new(PushConst, 1, loc),
    @opcode.Instruction::new(Jump, 5, loc),
    @opcode.Instruction::new(Ret, 0, loc),
  ])
  expect_violation(
    verify_compile_output(o, false),
    "stack-underflow",
    "块入口",
  )
}

///|
test "verify: 跳转越界" {
  let loc = @source.SourceLoc::new(1, 1)
  let o = with_main_body(mk_clean_output(), [
    @opcode.Instruction::new(Jump, 99, loc),
    @opcode.Instruction::new(PushConst, 0, loc),
    @opcode.Instruction::new(Ret, 0, loc),
  ])
  expect_violation(
    verify_compile_output(o, false),
    "jump-out-of-range",
    "越本函数段",
  )
}

///|
test "verify: 跳转跨段（进 wrapper）" {
  let loc = @source.SourceLoc::new(1, 1)
  // main 段 [1,4)；Jump 4 落 wrapper 段
  let o = with_main_body(mk_clean_output(), [
    @opcode.Instruction::new(Jump, 4, loc),
    @opcode.Instruction::new(PushConst, 0, loc),
    @opcode.Instruction::new(Ret, 0, loc),
  ])
  expect_violation(
    verify_compile_output(o, false),
    "jump-cross-segment",
    "越本函数段",
  )
}

///|
test "verify: FuncMeta arg_count 失锚" {
  let o = mk_clean_output()
  guard o.func_table.get("main") is Some(m) else {
    fail("夹具坏：无 main")
  }
  m.arg_count = 3
  expect_violation(
    verify_compile_output(o, false),
    "meta-inconsistent",
    "arg_count 3 ≠ Σparam_sizes 0",
  )
}

///|
test "verify: 局部偏移越帧" {
  let loc = @source.SourceLoc::new(1, 1)
  let o = mk_clean_output()
  guard o.func_table.get("main") is Some(m) else {
    fail("夹具坏：无 main")
  }
  m.local_count = 4
  let o = with_main_body(o, [
    @opcode.Instruction::new(LoadLocal, 8, loc),
    @opcode.Instruction::new(Ret, 0, loc),
  ])
  expect_violation(
    verify_compile_output(o, false),
    "ref-out-of-range",
    "LoadLocal 偏移 8(+4) 越帧 4",
  )
}

///|
test "verify: f64 常量池越界（PushConstD）" {
  let loc = @source.SourceLoc::new(1, 1)
  let o = mk_clean_output()
  let o = with_main_body(o, [
    @opcode.Instruction::new(PushConstD, 9, loc),
    @opcode.Instruction::new(Ret, 0, loc),
  ])
  expect_violation(
    verify_compile_output(o, false),
    "ref-out-of-range",
    "PushConstD 常量索引 9 越 f64_constants [0]",
  )
}

///|
test "verify: Call 目标不在值域" {
  let loc = @source.SourceLoc::new(1, 1)
  let o = with_main_body(mk_clean_output(), [
    @opcode.Instruction::new(Call, 500, loc),
    @opcode.Instruction::new(PushConst, 0, loc),
    @opcode.Instruction::new(Ret, 0, loc),
  ])
  expect_violation(
    verify_compile_output(o, false),
    "call-unknown-target",
    "Call 目标 500 不在 func_index 值域",
  )
}

///|
test "verify: 段尾非控制指令（穿段）" {
  let loc = @source.SourceLoc::new(1, 1)
  let o = with_main_body(mk_clean_output(), [
    @opcode.Instruction::new(PushConst, 0, loc),
    @opcode.Instruction::new(Pop, 0, loc),
  ])
  expect_violation(
    verify_compile_output(o, false),
    "segment-fallthrough",
    "段尾指令 Pop 非控制类",
  )
}

///|
test "verify: 零发射保留位出现在产物" {
  let loc = @source.SourceLoc::new(1, 1)
  let o = with_main_body(mk_clean_output(), [
    @opcode.Instruction::new(Strlen, 0, loc),
    @opcode.Instruction::new(PushConst, 0, loc),
    @opcode.Instruction::new(Ret, 0, loc),
  ])
  expect_violation(
    verify_compile_output(o, false),
    "reserved-opcode",
    "Strlen 是零发射保留位",
  )
}

///|
test "verify: code[0] 非 Jump（wrapper 缺失）" {
  let loc = @source.SourceLoc::new(1, 1)
  let o = mk_clean_output()
  o.code[0] = @opcode.Instruction::new(Nop, 0, loc)
  expect_violation(
    verify_compile_output(o, false),
    "wrapper-shape",
    "code[0] 不是 Jump",
  )
}

///|
test "verify: wrapper Call 目标错" {
  let loc = @source.SourceLoc::new(1, 1)
  let o = mk_clean_output()
  // 伪造第二个函数占用 1090——Call 1090 有值域但 ≠ main
  o.func_index.set("helper", 1090)
  o.func_table.set("helper", {
    ip: 1,
    arg_count: 0,
    param_count: 0,
    local_count: 0,
    param_sizes: [],
    return_type: @ast.Type::int(),
    is_variadic: false,
    local_buffers: [],
  })
  o.code[3] = @opcode.Instruction::new(Call, 1090, loc)
  expect_violation(
    verify_compile_output(o, false),
    "wrapper-shape",
    "≠ func_index[main]",
  )
}

///|
test "verify: string_data 地址重叠" {
  let o = mk_clean_output()
  o.string_data.push((0x1000U, "ab"))
  o.string_data.push((0x1001U, "cd"))
  let o = { ..o, global_data_end: 0x1100U, }
  expect_violation(
    verify_compile_output(o, false),
    "data-overlap",
    "重叠/乱序",
  )
}

///|
test "verify: 全局偏移越 global_data_end" {
  let loc = @source.SourceLoc::new(1, 1)
  let o = mk_clean_output()
  let o = { ..o, global_data_end: GLOBAL_START + 8U, }
  let o = with_main_body(o, [
    @opcode.Instruction::new(LoadGlobal, 16, loc),
    @opcode.Instruction::new(Ret, 0, loc),
  ])
  expect_violation(
    verify_compile_output(o, false),
    "ref-out-of-range",
    "越全局区",
  )
}

///|
/// else 块入口深回归（null_pointer_constant 形态实锤校准，2026-10-21）：
/// 无条件 Jump 的 fallthrough 是死路，else 块头深以 JumpIfZero 登记为
/// 权威——线性继承 then 路径深会假报 Ret 守恒红。
test "verify: 三元/条件表达式 else 块不假红" {
  let loc = @source.SourceLoc::new(1, 1)
  // cond ? 1 : 0 的标准形态：
  // [1]LoadLocal [2]PushConst [3]Eq [4]JumpIfZero 7 [5]PushConst(then)
  // [6]Jump 8 [7]PushConst(else) [8]Ret
  let o = with_main_body(mk_clean_output(), [
    @opcode.Instruction::new(LoadLocal, 0, loc),
    @opcode.Instruction::new(PushConst, 0, loc),
    @opcode.Instruction::new(Eq, 0, loc),
    @opcode.Instruction::new(JumpIfZero, 7, loc),
    @opcode.Instruction::new(PushConst, 1, loc),
    @opcode.Instruction::new(Jump, 8, loc),
    @opcode.Instruction::new(PushConst, 0, loc),
    @opcode.Instruction::new(Ret, 0, loc),
  ])
  // main 有一个局部（local_count=4 供 LoadLocal 0）
  guard o.func_table.get("main") is Some(m) else { fail("夹具坏") }
  m.local_count = 4
  let vs = verify_compile_output(o, false)
  assert_eq(
    vs.length(),
    0,
    msg="else 块形态必须零违约（入口权威化失效即假红）：\{verify_violations_json(vs)}",
  )
}
