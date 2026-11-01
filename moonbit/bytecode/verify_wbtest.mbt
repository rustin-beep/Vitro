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

// ═══════════════════════════════════════════════════════════════════════
// 审阅 v2 批 A2（2026-11-01）——M15 C-1 红锚覆盖缺口补齐（J9 会红义务）
// 规则总表 27 条中原 15 注入锚之外的检查点逐条注入违约；形态沿用
// kind+detail 双断言。两条特殊：
//  · L609 常规模式用户段 Call 栈深——**双形态锚**（当前被 `>=1000 无上界`
//    的 libc 判定吞成 Unknown，零违约；KNOWN_DIVERGENCE 注明 B 批翻面），
//    并以 library 模式同构造红锚证明规则本体活着（M15 E1/E1b 复刻）。
//  · wrapper_ip 远越界（E6 形态 wrapper_ip=99）当前自崩（Array::at panic，
//    M15 A-2），**本批不锚**——留 B 批修 verify_function_segment 访问顺序后
//    补；此处只锚 wrapper_ip=0 的结构化红形态（E6b）。
//  · 补锚过程实锤两条规则为**结构性死分支**（M15 规则总表 27 条实活 25）：
//    L359 段间无缝（idx≥1 不可达）/ L377 wrapper 起点（恒假）——对应锚改锁
//    真实兜底规则（L538 段尾非控制类 / L824 wrapper 越界），死分支登记 B 批。
// ═══════════════════════════════════════════════════════════════════════

///|
/// 双函数夹具（main 1089 + helper 1090，helper 两参）：
/// code：[0]Jump 6 / [1]Call 1090 [2]PushConst 0 [3]Ret（main 段 [1,4)）/
/// [4]PushConst 7 [5]Ret（helper 段 [4,6)）/ [6]Call 1089 [7]Ret（wrapper）。
/// main 体 Call helper 时栈深 0 却要弹 2——Call 栈深规则的违约构造。
fn mk_two_func_call_underflow() -> CompileOutput {
  let loc = @source.SourceLoc::new(1, 1)
  let o = mk_clean_output()
  let code : Array[@opcode.Instruction] = [
    @opcode.Instruction::new(Jump, 6, loc),
    @opcode.Instruction::new(Call, 1090, loc),
    @opcode.Instruction::new(PushConst, 0, loc),
    @opcode.Instruction::new(Ret, 0, loc),
    @opcode.Instruction::new(PushConst, 7, loc),
    @opcode.Instruction::new(Ret, 0, loc),
    @opcode.Instruction::new(Call, 1089, loc),
    @opcode.Instruction::new(Ret, 0, loc),
  ]
  o.func_index.set("helper", 1090)
  o.func_table.set("helper", {
    ip: 4,
    arg_count: 2,
    param_count: 2,
    local_count: 8,
    param_sizes: [1, 1],
    return_type: @ast.Type::int(),
    is_variadic: false,
    local_buffers: [],
  })
  { ..o, code, }
}

///|
/// KNOWN_DIVERGENCE（M15 A-1，verify.mbt:609）：常规模式下 `Call 1090`
/// （用户段）因 `operand >= BYTECODE_LIBC_BASE_INDEX` 无上界被整体判为
/// libc 段 → depth=Unknown → 栈深 0 弹 2 的违约**零报**。头注意图是
/// [1000,1088) 闭区间；真实产物用户段 idx 从 1089 递增（gen.mbt:133），
/// 故常规产物**所有**用户函数调用都落 Unknown——主战场检查面失效。
/// 本锚锁当前「零违约」行为；B 批按 meta 可得性改判（idx2meta 有 ⇒
/// 静态检查）后翻面为 `expect_violation(vs, "stack-underflow",
/// "Call 弹 2 word 但栈深仅 0")`（与下一条 library 模式锚同文案）。
test "verify: [KNOWN_DIVERGENCE] 常规模式用户段 Call 栈深被 libc 判定吞" {
  let vs = verify_compile_output(mk_two_func_call_underflow(), false)
  assert_eq(
    vs.length(),
    0,
    msg="当前行为=零违约（A-1 吞）；若此处红说明 A-1 已修，请翻面为 expect_violation：\{verify_violations_json(vs)}",
  )
}

///|
/// A-1 对照正锚：同一夹具 library 模式（无 `>=1000` 短路）走 idx2meta
/// 静态检查 → 红 underflow——证明 Call 栈深规则本体活着，只是常规模式
/// 的判定式把它关掉了（M15 E1b 复刻）。
test "verify: library 模式用户段 Call 栈深 underflow 红" {
  expect_violation(
    verify_compile_output(mk_two_func_call_underflow(), true),
    "stack-underflow",
    "Call 弹 2 word 但栈深仅 0",
  )
}

///|
test "verify: 字符串区末尾越 global_data_end" {
  let o = mk_clean_output()
  // 单条串从 GLOBAL_START 起 3 字节（"ab"+NUL），global_data_end 仍 =
  // GLOBAL_START ⇒ 末尾 0x1003 > 0x1000
  o.string_data.push((GLOBAL_START, "ab"))
  expect_violation(
    verify_compile_output(o, false),
    "data-overlap",
    "越 global_data_end",
  )
}

///|
test "verify: globals_init_32 越 MEM_SIZE" {
  let o = mk_clean_output()
  // 相对偏移 = MEM_SIZE - GLOBAL_START ⇒ 绝对 addr = MEM_SIZE，+4 越界
  o.globals_init_32.push((MEM_SIZE - GLOBAL_START, 0))
  expect_violation(
    verify_compile_output(o, false),
    "ref-out-of-range",
    "globals_init_32 偏移",
  )
}

///|
test "verify: globals_init_64 越 MEM_SIZE" {
  let o = mk_clean_output()
  o.globals_init_64.push((MEM_SIZE - GLOBAL_START, 0UL))
  expect_violation(
    verify_compile_output(o, false),
    "ref-out-of-range",
    "globals_init_64 偏移",
  )
}

///|
test "verify: 键集分叉——func_table 有而 func_index 无" {
  let o = mk_clean_output()
  o.func_table.set("ghost", {
    ip: 3,
    arg_count: 0,
    param_count: 0,
    local_count: 0,
    param_sizes: [],
    return_type: @ast.Type::int(),
    is_variadic: false,
    local_buffers: [],
  })
  expect_violation(
    verify_compile_output(o, false),
    "meta-inconsistent",
    "func_table 有而 func_index 无",
  )
}

///|
test "verify: 键集分叉——func_index 有而 func_table 无且非 libc 预注册" {
  let o = mk_clean_output()
  // 1089 是用户段（≥ 1000+88），不享受 libc 预注册豁免
  o.func_index.set("ghost", 1089)
  expect_violation(
    verify_compile_output(o, false),
    "meta-inconsistent",
    "func_index 有而 func_table 无",
  )
}

///|
test "verify: code 段为空" {
  let o = mk_clean_output()
  let o = { ..o, code: [], }
  expect_violation(
    verify_compile_output(o, false),
    "segment-fallthrough",
    "code 段为空",
  )
}

///|
test "verify: 首个函数段未从 ip=1 起" {
  let o = mk_clean_output()
  guard o.func_table.get("main") is Some(m) else { fail("夹具坏") }
  m.ip = 2
  expect_violation(
    verify_compile_output(o, false),
    "segment-fallthrough",
    "首个函数段未从 ip=1 起",
  )
}

///|
/// 段间游离指令形态。**审阅 v2 批 A2 结构性发现（M15 未列）**：规则总表
/// 「段间无缝 L359」`ip != expected_ip` 对 idx≥1 **不可达**——expected_ip
/// 每轮被赋为 seg_end = metas[idx+1].ip，下一轮的 ip 恒等于它；仅 idx=0
/// 可红且与 L345「首段非 1」完全重叠。游离指令实际由 L538「段尾非控制
/// 类」兜住（前一段的 seg_end 直抵下一函数 ip，游离指令成为前段段尾）。
/// 本锚锁真实兜底规则；L359 死分支登记给 B 批（删或改为 ip 重复检测）。
test "verify: 段间游离指令（由段尾非控制类兜住；L359 死分支登记）" {
  let loc = @source.SourceLoc::new(1, 1)
  let o = mk_clean_output()
  // main ip=1 / helper ip=4：main 段实为 [1,4)，[3] PushConst 9 成 main 段尾
  let code : Array[@opcode.Instruction] = [
    @opcode.Instruction::new(Jump, 6, loc),
    @opcode.Instruction::new(PushConst, 1, loc),
    @opcode.Instruction::new(Ret, 0, loc),
    @opcode.Instruction::new(PushConst, 9, loc),
    @opcode.Instruction::new(PushConst, 1, loc),
    @opcode.Instruction::new(Ret, 0, loc),
    @opcode.Instruction::new(Call, 1089, loc),
    @opcode.Instruction::new(Ret, 0, loc),
  ]
  o.func_index.set("helper", 1090)
  o.func_table.set("helper", {
    ip: 4,
    arg_count: 0,
    param_count: 0,
    local_count: 0,
    param_sizes: [],
    return_type: @ast.Type::int(),
    is_variadic: false,
    local_buffers: [],
  })
  let o = { ..o, code, }
  expect_violation(
    verify_compile_output(o, false),
    "segment-fallthrough",
    "段尾指令 PushConst 非控制类",
  )
}

///|
/// wrapper 起点错位形态。**审阅 v2 批 A2 结构性发现（M15 未列）**：规则
/// 总表「wrapper 起点 L377」`expected_ip != wrapper_ip` **恒假不可达**——
/// 最后函数的 seg_end 定义即 wrapper_ip（L367-371），expected_ip 赋值后
/// 恒等。错位形态实际由 L824「wrapper 越界」（wrapper_ip ≥ code 长）或
/// 段尾/栈守恒规则（wrapper_ip 落段内）兜住。本锚锁真实兜底规则；L377
/// 死分支登记给 B 批。
test "verify: wrapper 起点错位（由 wrapper 越界兜住；L377 死分支登记）" {
  let loc = @source.SourceLoc::new(1, 1)
  let o = mk_clean_output()
  // code 长 5，Jump 5 ⇒ main 段 [1,5) 段尾 Ret 合法、wrapper_ip=5 越界
  o.code[0] = @opcode.Instruction::new(Jump, 5, loc)
  expect_violation(
    verify_compile_output(o, false),
    "wrapper-shape",
    "wrapper 起点 5 越界（code 长 5）",
  )
}

///|
test "verify: FuncMeta ip=0 未注册陷阱位" {
  let o = mk_clean_output()
  guard o.func_table.get("main") is Some(m) else { fail("夹具坏") }
  m.ip = 0
  expect_violation(
    verify_compile_output(o, false),
    "meta-inconsistent",
    "ip=0（未注册陷阱位",
  )
}

///|
test "verify: FuncMeta param_sizes 含非正 word 数" {
  let o = mk_clean_output()
  guard o.func_table.get("main") is Some(m) else { fail("夹具坏") }
  m.param_sizes = [0]
  m.param_count = 1
  expect_violation(
    verify_compile_output(o, false),
    "meta-inconsistent",
    "param_sizes 含非正 word 数 0",
  )
}

///|
test "verify: FuncMeta param_count ≠ param_sizes 长度" {
  let o = mk_clean_output()
  guard o.func_table.get("main") is Some(m) else { fail("夹具坏") }
  m.param_sizes = [1]
  m.arg_count = 1
  m.local_count = 4
  // param_count 仍 0
  expect_violation(
    verify_compile_output(o, false),
    "meta-inconsistent",
    "param_count 0 ≠ param_sizes 长度 1",
  )
}

///|
test "verify: FuncMeta local_count 不覆盖参数区" {
  let o = mk_clean_output()
  guard o.func_table.get("main") is Some(m) else { fail("夹具坏") }
  // 两参 8 word = 32 字节，local_count 4 不够
  m.param_sizes = [4, 4]
  m.param_count = 2
  m.arg_count = 8
  m.local_count = 4
  expect_violation(
    verify_compile_output(o, false),
    "ref-out-of-range",
    "local_count 4 不覆盖参数区 32 字节",
  )
}

///|
test "verify: local_buffer 越帧（正尺寸）" {
  let o = mk_clean_output()
  guard o.func_table.get("main") is Some(m) else { fail("夹具坏") }
  m.local_count = 8
  m.local_buffers.push({ offset: 0, size: 24, name: "buf", })
  expect_violation(
    verify_compile_output(o, false),
    "ref-out-of-range",
    "local_buffer 'buf' [0,24) 越帧 8",
  )
}

///|
test "verify: i64 常量池越界（PushConstQ）" {
  let loc = @source.SourceLoc::new(1, 1)
  let o = with_main_body(mk_clean_output(), [
    @opcode.Instruction::new(PushConstQ, 9, loc),
    @opcode.Instruction::new(Ret, 0, loc),
  ])
  expect_violation(
    verify_compile_output(o, false),
    "ref-out-of-range",
    "PushConstQ 常量索引 9 越 i64_constants [0]",
  )
}

///|
test "verify: TrapBounds 符号下标越界" {
  let loc = @source.SourceLoc::new(1, 1)
  // TrapBounds 零栈效应，可直接夹在 PushConst/Ret 之间
  let o = with_main_body(mk_clean_output(), [
    @opcode.Instruction::new(PushConst, 0, loc),
    @opcode.Instruction::new(TrapBounds, 3, loc),
    @opcode.Instruction::new(Ret, 0, loc),
  ])
  expect_violation(
    verify_compile_output(o, false),
    "ref-out-of-range",
    "TrapBounds 符号下标 3 越 symbols [0]",
  )
}

///|
test "verify: wrapper——func_index 无 main" {
  let o = mk_clean_output()
  o.func_index.remove("main")
  expect_violation(
    verify_compile_output(o, false),
    "wrapper-shape",
    "func_index 无 main",
  )
}

///|
test "verify: wrapper——PushArgv/PushArgc 前缀与 main 参数数不匹配" {
  let o = mk_clean_output()
  guard o.func_table.get("main") is Some(m) else { fail("夹具坏") }
  // main 两参（argc/argv）但 wrapper 无 PushArgv/PushArgc 前缀
  m.param_sizes = [1, 1]
  m.param_count = 2
  m.arg_count = 2
  m.local_count = 8
  expect_violation(
    verify_compile_output(o, false),
    "wrapper-shape",
    "前缀(false) 与 main 参数数(2) 不匹配",
  )
}

///|
test "verify: wrapper——Call 后有多余指令（段尾非 Ret）" {
  let loc = @source.SourceLoc::new(1, 1)
  let o = mk_clean_output()
  // wrapper [3,6)：Call Ret Nop——Call 后不是紧接段尾 Ret
  o.code.push(@opcode.Instruction::new(Nop, 0, loc))
  expect_violation(
    verify_compile_output(o, false),
    "wrapper-shape",
    "wrapper 段尾非 Ret 或 Call 后有多余指令",
  )
}

///|
/// wrapper_ip 越界的**结构化红**形态（M15 E6b：wrapper_ip=0 < 1）。远越界
/// 形态（wrapper_ip ≥ code.length()+1，E6）当前在 verify_function_segment
/// L538 先行 `code[seg_end-1]` 自崩（A-2），本批不锚——B 批前移越界检查后
/// 补「wrapper_ip=99 必红不崩」锚。
test "verify: wrapper 起点越界（wrapper_ip=0）" {
  let loc = @source.SourceLoc::new(1, 1)
  let o = mk_clean_output()
  o.code[0] = @opcode.Instruction::new(Jump, 0, loc)
  expect_violation(
    verify_compile_output(o, false),
    "wrapper-shape",
    "wrapper 起点 0 越界",
  )
}
