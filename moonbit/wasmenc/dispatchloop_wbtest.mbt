// dispatchloop_wbtest —— 批 4a 组装器结构锚（WInstr 层——骨架/深度/
// 步锚/G_RV 通道/帧协议的指令级断言；实跑验证归 4b 的 V8/wasmtime 闸，
// wasmenc 包测试无宿主不起实例）。

///|
fn d4_ctx() -> EmitCtx {
  {
    f64_constants: [1.5, -0.25],
    i64_constants: [42L, -1L],
    argc: 1,
    argv_addr: 0x4000,
    fallthrough_pc: 77,
    host_argv_ptr: 0x5000,
    symbol_sizes: [4, 10],
  }
}

///|
/// 最小程序（`return 42` 形态：入口 Jump 到 main 体？——直接最小可跑序：
/// PushConst 42; Ret）的骨架结构锚：入口初始化 + 单块 + 出口块 + 哨兵。
test "dispatch_minimal_program_skeleton" {
  // 程序：gip0 = PushConst(42)、gip1 = Ret(0)；入口 0
  let input : DispatchInput = {
    ops: [PushConst, Ret],
    operands: [42, 0],
    func_entry_ips: [0],
    entry_ip: 0,
    call_sites: Map([]),
    stack_start: 1048576,
    call_depth_limit: 10000,
    max_steps: 100000,
    ctx: d4_ctx(),
  }
  let r = assemble_dispatch_body(input)
  guard r is Ok(body) else { fail("组装须绿") }
  // ——结构断言（WInstr 层镜像）——
  // ①入口初始化序列：pc=start_ip（local0→G_PC）+ 哨兵帧头三 store +
  //   FB/DEPTH 复位（16 条）+ loop + 块结构
  assert_true(body.length() > 20, msg="骨架非空")
  assert_true(
    body[0] is WI32Const(0) && body[1] is WGlobalSet(_),
    msg="入口首两条 = entry 烧死入 pc（P2-4 无参化——原 local.get 0 撞模板槽）",
  )
  // ②br_table 在场（分发核心）且标签向量含出口块（末项 = 块数）
  let mut has_br_table = false
  for w in body {
    if w is WBrTable(labels, _) {
      has_br_table = true
      // ip 空间 0..2（exit_ip=2）：T[0]=块 0、T[1]=default（非 leader）、
      // T[2]=出口块（nblocks=1 → 标签 1）
      assert_eq(
        labels,
        [0, 2, 2],
        msg="标签向量（P1-c：出口 = EXIT block 深度 nblocks+1）",
      )
    }
  }
  assert_true(has_br_table, msg="br_table 必在")
  // ③出口块：global.get G_RV + return（序列末段——unreachable 前）
  let mut exit_seen = false
  for i = 0; i < body.length() - 1; i = i + 1 {
    if body[i] is WGlobalGet(_) && body[i + 1] is WReturn {
      exit_seen = true
    }
  }
  assert_true(exit_seen, msg="出口块 return G_RV 必在")
  // ④模块字节形态（magic + version 头 + 0x0E 码位经 build 校验——
  //   此处至少验证 build 可产非空字节）
  let input2 : DispatchInput = {
    ops: [PushConst, Ret],
    operands: [42, 0],
    func_entry_ips: [0],
    entry_ip: 0,
    call_sites: Map([]),
    stack_start: 1048576,
    call_depth_limit: 10000,
    max_steps: 100000,
    ctx: d4_ctx(),
  }
  let bytes = assemble_dispatch_module(input2)
  guard bytes is Ok(bs) else { fail("模块字节须绿") }
  assert_eq(bs[0], b'\x00', msg="wasm magic 首字节")
  assert_eq(bs[1], b'a', msg="wasm magic")
}

///|
/// 调用协议锚：Call 展开（参数搬运/帧头三写/指针更新/br 深度）+ Ret 展开
/// （G_RV 通道/帧头三读）+ 返回点块首 load（非 void）。
test "dispatch_call_ret_protocol" {
  // 程序：main（gip0）= PushConst 7; Call f(4); PushConst 0; Ret
  //       f（gip4）= PushConst 9; Ret（Ret 前压返回值——VM pop 语义）
  let input : DispatchInput = {
    ops: [PushConst, Call, PushConst, Ret, PushConst, Ret],
    operands: [7, 4, 0, 0, 9, 0],
    func_entry_ips: [0, 4],
    entry_ip: 0,
    call_sites: Map([]),
    stack_start: 1048576,
    call_depth_limit: 10000,
    max_steps: 100000,
    ctx: d4_ctx(),
  }
  input.call_sites.set(1, {
    target_ip: 4,
    arg_words: 1,
    frame_bytes: 8,
    param_words: [1],
    is_void: false,
  })
  let r = assemble_dispatch_body(input)
  guard r is Ok(body) else { fail("组装须绿") }
  // ①返回点 load G_RV：非 void 调用一次 → 序列里 WGlobalGet(G_RV)
  //   恰 2 次（返回点块首 1 + 出口块 1）——fill(h_in) 插在步锚与 load
  //   之间（溢出池架构修正后的块首序：步锚 → fill → load）
  let mut rv_gets = 0
  for w in body {
    if w is WGlobalGet(G_RV) {
      rv_gets = rv_gets + 1
    }
  }
  assert_eq(rv_gets, 2, msg="返回点 load + 出口 return 各一次")
  // ②Ret 展开含帧头三读（三个 i32.load 序列特征：G_FB 相关 load ≥3）
  let mut fb_loads = 0
  for i = 0; i < body.length() - 1; i = i + 1 {
    if body[i] is WGlobalGet(G_FB) && body[i + 1] is WI32Const(_) {
      fb_loads = fb_loads + 1
    }
  }
  assert_true(
    fb_loads >= 6,
    msg="两处 Ret 的帧头三读（FB 相关 ≥6——实得 \{fb_loads}）",
  )
  // ③Call 展开含深度检查（G_DEPTH 比较特征：global.get G_DEPTH 在场）
  let mut depth_check = false
  for w in body {
    if w is WGlobalGet(G_DEPTH) {
      depth_check = true
    }
  }
  assert_true(depth_check, msg="深度上限检查必在")
}

///|
/// J9：CallPtr 透传禁译红（partition 拦——组装器不静默）。
test "dispatch_callptr_red" {
  let input : DispatchInput = {
    ops: [CallPtr],
    operands: [0],
    func_entry_ips: [0],
    entry_ip: 0,
    call_sites: Map([]),
    stack_start: 1048576,
    call_depth_limit: 10000,
    max_steps: 100000,
    ctx: d4_ctx(),
  }
  let r = assemble_dispatch_body(input)
  assert_true(
    r is Err(Blocks(CallPtrUnsupported(_))),
    msg="CallPtr 必透传禁译红",
  )
}

///|
/// J9：返回点元数据缺失（Call 无 call_sites 登记）→ BadReturnPoint 红。
test "dispatch_missing_call_site_red" {
  let input : DispatchInput = {
    ops: [Call, PushConst, Ret],
    operands: [1, 0, 0],
    func_entry_ips: [0, 1],
    entry_ip: 0,
    call_sites: Map([]), // 缺 gip0 的登记（栈空闸按 0 word 过——到返回点检查红）
    stack_start: 1048576,
    call_depth_limit: 10000,
    max_steps: 100000,
    ctx: d4_ctx(),
  }
  let r = assemble_dispatch_body(input)
  assert_true(
    r is Err(BadReturnPoint(_, _)),
    msg="调用点元数据缺失必红",
  )
}
