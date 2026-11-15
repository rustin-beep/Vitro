// dispatch_project_wbtest —— 批 4b-1 投影层锚（libc 全量真实投影 +
// Call operand 重写 + J9 变参禁译红）。

///|
/// 最小 CompileOutput（code 可带——全 libc 投影面与单函数形态共用）。
fn dp_out(
  code : Array[@opcode.Instruction],
  funcs : Array[(String, Int32, @bytecode.FuncMeta)],
) -> @bytecode.CompileOutput {
  let ft : Map[String, @bytecode.FuncMeta] = Map([])
  let fi : Map[String, Int32] = Map([])
  for e in funcs {
    ft.set(e.0, e.2)
    fi.set(e.0, e.1)
  }
  {
    code,
    globals_init_32: [],
    globals_init_64: [],
    func_table: ft,
    func_index: fi,
    string_data: [],
    source_map: [],
    symbols: [],
    struct_defs: Map([]),
    union_defs: Map([]),
    f64_constants: [],
    i64_constants: [],
    global_data_end: 0U,
  }
}

///|
/// 全 libc 投影锚：真实 LibcArtifact（88 函数预编译产物）整体投影——
/// libc 内部静态调用点全部可解、无变参/CallPtr（实测口径——若 libc
/// 演化引入禁译形态，本锚红即传染面警报）。
test "dispatch_project_libc_full_green" {
  let r = build_dispatch_input(dp_out([], []), 100000)
  assert_true(
    r is Ok(_),
    msg="全 libc 投影须绿——libc 演化引入禁译形态时本锚即传染面警报",
  )
  guard r is Ok(input) else { fail("见上断言") }
  // DCE（批 4b-1）：空用户无静态调用 → libc 全剪——组数 0、入口 0
  assert_eq(input.ops.length(), 0, msg="DCE 后组数 0（libc 全剪）")
  assert_eq(input.entry_ip, 0, msg="入口 = 用户基址（空程序）")
}

///|
/// Call operand 重写锚：用户 Call(func_idx) → 目标 ip（用户函数
/// m.ip + libc_len）+ call_sites 登记（arg_words/frame_bytes/void 位）。
test "dispatch_project_call_rewrite" {
  // 用户函数 f：入口 ip=1（用户区）、1 个 i32 参、8B 帧、非 void；
  // 用户 code：PushConst 3; Call 5; PushConst 0; Ret
  let fmeta : @bytecode.FuncMeta = {
    ip: 1,
    arg_count: 1,
    param_count: 1,
    local_count: 8,
    param_sizes: [1],
    return_type: @ast.Type::Int(false, false),
    param_types: [],
    is_variadic: false,
    local_buffers: [],
  }
  let out = dp_out(
    [
      @opcode.Instruction::new(PushConst, 3, @source.SourceLoc::new(1, 1)),
      @opcode.Instruction::new(Call, 5, @source.SourceLoc::new(1, 1)),
      @opcode.Instruction::new(PushConst, 0, @source.SourceLoc::new(2, 1)),
      @opcode.Instruction::new(Ret, 0, @source.SourceLoc::new(2, 1)),
    ],
    [("f", 5, fmeta)],
  )
  let r = build_dispatch_input(out, 100000)
  guard r is Ok(input) else { fail("投影须绿") }
  // DCE 后用户基 = 0：Call@1 operand 重写 = 目标 ip（用户函数 ip=1）
  assert_eq(input.operands[1], 1, msg="Call operand 重写为目标 ip")
  let site = input.call_sites.get(1)
  assert_true(site is Some(_), msg="call_sites 登记")
  guard site is Some(s) else { fail("见上") }
  assert_eq(s.arg_words, 1, msg="arg_words = param_sizes 和")
  assert_eq(s.frame_bytes, 8, msg="frame_bytes = local_count")
  assert_false(s.is_void, msg="非 void（返回点 load G_RV）")
}

///|
/// J9：变参目标禁译红（CallVar 的运行期 argc 语义不在静态域——
/// fail loud 归 4b 闸禁译登记，不静默）。
test "dispatch_project_variadic_red" {
  let vmeta : @bytecode.FuncMeta = {
    ip: 1,
    arg_count: 1,
    param_count: 1,
    local_count: 8,
    param_sizes: [1],
    return_type: @ast.Type::Void(false),
    param_types: [],
    is_variadic: true,
    local_buffers: [],
  }
  let out = dp_out(
    [
      @opcode.Instruction::new(PushConst, 1, @source.SourceLoc::new(1, 1)),
      @opcode.Instruction::new(Call, 5, @source.SourceLoc::new(1, 1)),
      @opcode.Instruction::new(RetVoid, 0, @source.SourceLoc::new(2, 1)),
    ],
    [("v", 5, vmeta)],
  )
  let r = build_dispatch_input(out, 100000)
  assert_true(r is Err(NotSupported(_)), msg="变参目标必红")
}

///|
/// data blob 锚：globals_init_32 + string_data 的稠密投影（word 拆小端
/// 四字节、字符串逐字节并字）。
test "dispatch_project_data_blob" {
  // 最小 code（rc=0 程序——空 code 形态的入口=组数越界是组装边界，
  // data blob 锚不涉该面）
  let out = dp_out(
    [
      @opcode.Instruction::new(PushConst, 0, @source.SourceLoc::new(1, 1)),
      @opcode.Instruction::new(Ret, 0, @source.SourceLoc::new(1, 1)),
    ],
    [],
  )
  // globals_init/string_data 是 Array 字段（push 可变操作——无需 mut 绑定）。
  // globals_init_32 的 pair.0 是**相对 GLOBAL_START（0x1000）的偏移**（4b-2
  // 勘正：VM set_globals_32 与 LoadGlobal 模板 OpBase(0x1000) 同口径——
  // 投影曾漏加基址致 V8 读全局恒 0，e2_guarded_mutual 例 return_value 0
  // vs 引擎 8 实锤）；string_data 的地址是绝对值（codegen intern 产出）。
  out.globals_init_32.push((0x8U, 0x41424344))
  out.string_data.push((0x2008U, "AB"))
  guard build_dispatch_input(out, 100000) is Ok(di) else {
    fail("投影须绿")
  }
  assert_eq(di.ops.length(), 2, msg="DCE 后组数 = 2（libc 全剪）")
  let r = build_dispatch_product(out, 100000)
  guard r is Ok(p) else {
    match r {
      Err(m) => fail("产物须绿：" + m)
      Ok(_) => fail("unreachable")
    }
  }
  assert_eq(p.data_base, 0x1008, msg="blob 基址 = GLOBAL_START + 首偏移")
  // word 0x41424344 → 小端 44 43 42 41（@0x1008）；空洞 0x100c..0x2007 零铺；
  // "AB" + NUL @ 0x2008 → 41 42 00 + 尾零
  assert_eq(
    p.data_blob.length(),
    0x2008 - 0x1008 + 4,
    msg="blob 长 = 首末写区间稠密投影",
  )
  assert_eq(p.data_blob[0], b'\x44', msg="小端首字节")
  assert_eq(p.data_blob[4], b'\x00', msg="空洞零铺")
  assert_eq(p.data_blob[0x1000], b'A', msg="字符串首字节")
  assert_eq(p.data_blob[0x1002], b'\x00', msg="NUL 终止")
  // argv0 精化锚（4b-2）：真值形态 argc=1 + argv 区自 GLOBAL_REGION_LIMIT
  // 向下（R1 ③ footprint 口径）+ ctx 槽真值——空 argv0 保近似（argc=0）
  guard build_dispatch_input(out, 100000, argv0="x") is Ok(di2) else {
    fail("argv0 投影须绿")
  }
  assert_eq(di2.ctx.argc, 1, msg="argc 真值")
  let fp = @bytecode.argv_region_footprint(1, ["x"])
  assert_eq(
    di2.ctx.argv_addr,
    (@bytecode.GLOBAL_REGION_LIMIT - fp).reinterpret_as_int(),
    msg="argv_addr = GLOBAL_REGION_LIMIT - footprint",
  )
  let r2 = build_dispatch_product(out, 100000, argv0="x")
  guard r2 is Ok(p2) else { fail("argv0 产物须绿") }
  // argv 铺设进 blob（R1 ③ 编址）+ 产物新字段（4b-2）
  assert_eq(p2.host_calls, 0, msg="零 host 例计数")
  assert_eq(p2.max_steps, 100000, msg="预算透传")
}
