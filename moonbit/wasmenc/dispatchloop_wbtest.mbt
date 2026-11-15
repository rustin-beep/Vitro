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
    ret_kinds: Map([]),
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
    ret_kinds: Map([]),
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
    ret_kinds: Map([]),
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
    param_kinds: [VkWordI32],
    is_void: false,
    ret_kind: VkWordI32,
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
    ret_kinds: Map([]),
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
    call_sites: Map([]),
    ret_kinds: Map([]), // 缺 gip0 的登记（栈空闸按 0 word 过——到返回点检查红）
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

///|
/// 批 4b-2 锚①：StepEvent 零发射——dispatch 形态计步由块首批量步锚单源
/// 覆盖（模板的 steps+=1 四条序列是微缩/往返形态；双计实锤：V8 steps=11
/// vs 引擎 9，差值 = 块内 StepEvent 数）。断言：块体对 G_STEPS 的
/// global.set 恰 1 处（块锚）——修前（走模板）每 StepEvent 组多 1 处。
test "dispatch_step_event_zero_emission" {
  let input : DispatchInput = {
    ops: [StepEvent, StepEvent, PushConst, Ret],
    operands: [5, 6, 42, 0],
    func_entry_ips: [0],
    entry_ip: 0,
    call_sites: Map([]),
    ret_kinds: Map([]),
    stack_start: 1048576,
    call_depth_limit: 10000,
    max_steps: 100000,
    ctx: d4_ctx(),
  }
  let r = assemble_dispatch_body(input)
  guard r is Ok(body) else { fail("组装须绿") }
  let mut g_steps_sets = 0
  for w in body {
    if w is WGlobalSet(G_STEPS) {
      g_steps_sets = g_steps_sets + 1
    }
  }
  assert_eq(
    g_steps_sets,
    1,
    msg="G_STEPS 写恰 1 处（块锚单源——StepEvent 模板序列零发射）",
  )
}

///|
/// 批 4b-2 锚②：Memset 独立展开——value 暂存 i32 域（L_A），不经 L_T64
/// i64 过桥（模板形态在真实发射序与 i32 生产者错配——V8/wabt 编译红
/// 实锤 local.set[i64] 吃 i32）。断言：含 Memset 组的产物 body 中
/// L_T64 零消费（本输入无 Q 族——修前模板臂必现 WLocalGet/Set(L_T64)）
/// 且 memory.fill 在场。
test "dispatch_memset_i32_staging" {
  // vitro 栈序 [addr(底), value, size(顶)]——exec_memory Memset 弹序镜像
  let input : DispatchInput = {
    ops: [PushConst, PushConst, PushConst, Memset, Pop, PushConst, Ret],
    operands: [0x2000, 0x41, 8, 0, 0, 0, 0],
    func_entry_ips: [0],
    entry_ip: 0,
    call_sites: Map([]),
    ret_kinds: Map([]),
    stack_start: 1048576,
    call_depth_limit: 10000,
    max_steps: 100000,
    ctx: d4_ctx(),
  }
  let r = assemble_dispatch_body(input)
  guard r is Ok(body) else { fail("组装须绿") }
  let mut l_t64_refs = 0
  let mut has_fill = false
  for w in body {
    if w is WLocalGet(L_T64) || w is WLocalSet(L_T64) {
      l_t64_refs = l_t64_refs + 1
    }
    if w is WMemoryFill {
      has_fill = true
    }
  }
  assert_eq(
    l_t64_refs,
    0,
    msg="L_T64 零消费（value 走 L_A i32 槽——i64 过桥臂必红）",
  )
  assert_true(has_fill, msg="memory.fill 在场（语义同模板）")
}

///|
/// 批 4b-4 锚③：参数搬运**声明序**弹存——do_call_inner 同构（param_sizes
/// 声明序逐参、参内高 word 先弹；压栈右→左、左参在顶）。修前「逆序先
/// 弹」错位实锤：t3 减法例（`sub2(7,3)`）V8 rc=-4 vs 引擎 4——加法交换
/// 律长期掩盖。断言：双参搬运的两组 store 序中，param0 的帧偏移常量先现
/// （frame_bytes-0 先于 frame_bytes-4——声明序发射）。
test "dispatch_call_param_order" {
  let sites : Map[Int32, CallSiteMeta] = Map([])
  sites.set(2, {
    target_ip: 5,
    arg_words: 2,
    frame_bytes: 8,
    param_words: [1, 1],
    param_kinds: [VkWordI32, VkWordI32],
    is_void: false,
    ret_kind: VkWordI32,
  })
  // main：PushConst 7; PushConst 3; Call sub; PushConst 0; Ret
  // sub（gip5）：LoadLocal 0; LoadLocal 4; Sub; Ret
  let input : DispatchInput = {
    ops: [
      PushConst,
      PushConst,
      Call,
      PushConst,
      Ret,
      LoadLocal,
      LoadLocal,
      Sub,
      Ret,
    ],
    operands: [7, 3, 5, 0, 0, 0, 4, 0, 0],
    func_entry_ips: [0, 5],
    entry_ip: 0,
    call_sites: sites,
    ret_kinds: Map([]),
    stack_start: 1048576,
    call_depth_limit: 10000,
    max_steps: 100000,
    ctx: d4_ctx(),
  }
  let r = assemble_dispatch_body(input)
  guard r is Ok(body) else { fail("组装须绿") }
  // 搬运 store 特征：`WI32Const(frame_bytes - woff*4)` 后随 G_SPT/sub/加
  // 与 WI32Store。收集「frame_bytes-woff*4 形态」的常量出现序（8-0=8 先
  // 于 8-4=4 = 声明序 param0 先）。
  let order : Array[Int32] = []
  for i = 0; i < body.length(); i = i + 1 {
    // 搬运特征：WGlobalGet(G_SPT) 后随 WI32Const(frame_bytes - woff*4)
    if body[i] is WGlobalGet(G_SPT) &&
      i + 1 < body.length() &&
      body[i + 1] is WI32Const(c) {
      if c == 8 || c == 4 {
        order.push(c)
      }
    }
  }
  // frame_bytes=8：param0 woff=0 → const 8；param1 woff=1 → const 4
  assert_eq(
    order,
    [8, 4],
    msg="搬运 store 声明序（param0 帧偏移先发——修前逆序 [4,8] 错位）",
  )
}

///|
/// 批 4b-4 锚④：宽返回通道（VkF64）——Ret 存侧走 G_RV_W（L_TF 暂存 +
/// i64.reinterpret 过桥）+ 返回点 load 侧 G_RV_W + f64.reinterpret 回域。
/// 修前缺陷：G_RV 是 i32 槽装不下 f64 返回值（dsum 例 V8 编译红
/// `local.set[0] expected type f64`——wide-param 禁译曾掩盖该面）。
test "dispatch_wide_ret_channel_f64" {
  let sites : Map[Int32, CallSiteMeta] = Map([])
  sites.set(0, {
    target_ip: 4,
    arg_words: 0,
    frame_bytes: 8,
    param_words: [],
    param_kinds: [],
    is_void: false,
    ret_kind: VkF64,
  })
  // main：Call f; Pop(返回值); PushConst 0; Ret；f：PushConstD(1.5); Ret
  let rk : Map[Int32, WValKind] = Map([])
  rk.set(5, VkF64) // f 的 Ret（VkF64 存侧）
  let input : DispatchInput = {
    ops: [Call, Pop, PushConst, Ret, PushConstD, Ret],
    operands: [4, 0, 0, 0, 0, 0],
    func_entry_ips: [0, 4],
    entry_ip: 0,
    call_sites: sites,
    ret_kinds: rk,
    stack_start: 1048576,
    call_depth_limit: 10000,
    max_steps: 100000,
    ctx: d4_ctx(),
  }
  let r = assemble_dispatch_body(input)
  guard r is Ok(body) else { fail("组装须绿") }
  // Ret 存侧：L_TF 暂存 + reinterpret + G_RV_W
  let mut has_store = false
  for i = 0; i + 3 < body.length(); i = i + 1 {
    if body[i] is WLocalSet(L_TF) &&
      body[i + 2] is WI64ReinterpretF64 &&
      body[i + 3] is WGlobalSet(G_RV_W) {
      has_store = true
    }
  }
  assert_true(
    has_store,
    msg="Ret 存侧 f64 过桥（L_TF→reinterpret→G_RV_W）",
  )
  // 返回点 load 侧：G_RV_W + f64.reinterpret_i64
  let mut has_load = false
  for i = 0; i + 1 < body.length(); i = i + 1 {
    if body[i] is WGlobalGet(G_RV_W) && body[i + 1] is WF64ReinterpretI64 {
      has_load = true
    }
  }
  assert_true(
    has_load,
    msg="返回点 load f64 回域（G_RV_W→f64.reinterpret）",
  )
}
