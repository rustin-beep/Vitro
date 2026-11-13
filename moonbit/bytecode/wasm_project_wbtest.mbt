///|
/// REHOST 批 1c 投影层白盒：triples 保序 / EmitCtx 装配（池直填 + 尺寸表
/// + H2 窗口对齐）/ build_wasm_product Ok 路径（组表↔字节 verify 双通道
/// 核对过）/ Reserved 拒载定位（EmitFailed 携 gip——失败定位循环）。

///|
/// 最小产物（verify_wbtest 的 mk_clean_output 同形）：[0]Jump 3 /
/// [1]PushConst 42 / [2]Ret / [3]Call 1089 / [4]Ret。
fn mk_wasm_output() -> CompileOutput {
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
    struct_defs: Map([]),
    union_defs: Map([]),
    f64_constants: [1.5],
    i64_constants: [42L],
    global_data_end: 0x1000U,
  }
}

///|
test "wasm_triples 保序透传" {
  let o = mk_wasm_output()
  let t = wasm_triples(o)
  assert_eq(t.length(), 5, msg="组数 = code 条数")
  assert_eq(t[0].0, Jump, msg="首组身份")
  assert_eq(t[1].1, 42, msg="operand 透传")
  assert_eq(t[4].0, Ret, msg="末组身份")
  assert_eq(t[2].2.line, 1, msg="loc 透传")
}

///|
test "wasm_emit_ctx 装配口径" {
  let base = mk_wasm_output()
  // 符号尺寸表（元素数口径——vm/exec_debug.mbt:96 同源，PR #505 审阅 P1-1）：
  // int 非数组恒 0 + double 数组[3] → 3（首版误用字节数 4/24 已翻案）
  let symbols : Array[Symbol] = []
  symbols.push({
    name: "a",
    addr: 0x1000U,
    is_local: false,
    ty: @ast.Type::int(),
    scope_depth: 0,
    func_name: "",
    decl_line: 1,
  })
  symbols.push({
    name: "d",
    addr: 0x1004U,
    is_local: false,
    ty: @ast.Type::array_of(@ast.Type::Double(false), [3]),
    scope_depth: 0,
    func_name: "",
    decl_line: 2,
  })
  // H2 窗口对齐：0x1001 → 0x1004（4 对齐上取整）
  let o : CompileOutput = { ..base, symbols, global_data_end: 0x1001U, }
  let ctx = wasm_emit_ctx(o)
  assert_eq(ctx.f64_constants.length(), 1, msg="f64 池直填")
  assert_eq(ctx.f64_constants[0], 1.5, msg="f64 池值")
  assert_eq(ctx.i64_constants[0], 42L, msg="i64 池值")
  assert_eq(ctx.symbol_sizes[0], 0, msg="int 非数组元素数恒 0")
  assert_eq(ctx.symbol_sizes[1], 3, msg="double[3] 元素数")
  assert_eq(ctx.host_argv_ptr, 0x1004, msg="H2 窗口 4 对齐")
  assert_eq(ctx.argc, 0, msg="批 1c 近似面：argc=0")
  assert_eq(
    ctx.fallthrough_pc,
    0,
    msg="批 1c 近似面：fallthrough=0（批 2 基块划分器）",
  )
}

///|
test "build_wasm_product Ok 路径 + 装载核对双通道" {
  let o = mk_wasm_output()
  let ctx = wasm_emit_ctx(o)
  match build_wasm_product(o) {
    Ok(p) => {
      assert_eq(p.table.groups.length(), 5, msg="组表 1:1")
      assert_true(p.bytes.length() > 0, msg="字节流非空")
      // 双通道边界（批 1b 定形）：盲折叠匹配表只收 Exact+Composed——
      // 本产物含 C 类组（Jump/Ret/Call），盲折叠通道按设计拒载（防歧义
      // 污染 A/B 可解释面）；全态可裁决的通道是组表引导裁决（下断言）
      match @wasmenc.verify_group_table(p.table, p.bytes, ctx) {
        Ok(_) =>
          fail(
            "含 C 类组的产物盲折叠应拒载（匹配表设计不含 C）",
          )
        Err(_) => ()
      }
      match @wasmenc.verify_fold_with_table(p.table, p.bytes, ctx) {
        Ok(groups) =>
          assert_eq(groups.length(), 5, msg="引导裁决组数 = 侧车组数")
        Err(_) => fail("verify_fold_with_table 应过")
      }
    }
    Err(EmitFailed(g, n, r)) =>
      fail("最小产物应可发射：gip=\{g} op=\{n} reason=\{r}")
  }
}

///|
test "build_wasm_product Reserved 拒载定位（EmitFailed 携 gip）" {
  let base = mk_wasm_output()
  // [1] 处插 TryBegin（C# 保留位——发射器永久拒载）
  let code : Array[@opcode.Instruction] = [base.code[0]]
  code.push(@opcode.Instruction::new(TryBegin, 0, @source.SourceLoc::new(1, 1)))
  for i = 2; i < base.code.length(); i = i + 1 {
    code.push(base.code[i])
  }
  let o : CompileOutput = { ..base, code, }
  match build_wasm_product(o) {
    Ok(_) => fail("Reserved 指令应拒载")
    Err(EmitFailed(gip, op_name, reason)) => {
      assert_eq(gip, 1, msg="失败组定位 = TryBegin 所在序号")
      assert_eq(op_name, "TryBegin", msg="失败组身份")
      assert_true(
        reason.contains("NotImplemented"),
        msg="拒载原因（Reserved 永久拒载）: \{reason}",
      )
    }
  }
}

///|
/// REHOST 批 2b 装载往返锚：code → 发射 → 折叠 → 重建 → 恒等——
/// C 类组（Jump/Call/Ret 侧车身份）+ 多档 loc（侧车 loc 重建面）全覆盖。
test "rehost_round_trip 恒等往返" {
  let base = mk_wasm_output()
  // 多档 loc + file_id（侧车 loc 重建的消费面——恒一档测不出重建错位）
  let code : Array[@opcode.Instruction] = []
  let locs = [
    @source.SourceLoc::with_file(1, 1, 0),
    @source.SourceLoc::with_file(2, 5, 0),
    @source.SourceLoc::with_file(3, 9, 0),
    @source.SourceLoc::with_file(7, 2, 1),
    @source.SourceLoc::with_file(8, 4, 1),
  ]
  let ops : Array[@opcode.OpCode] = [Jump, PushConst, Ret, Call, Ret]
  let operands : Array[Int32] = [3, 42, 0, 1089, 0]
  for i = 0; i < 5; i = i + 1 {
    code.push(@opcode.Instruction::new(ops[i], operands[i], locs[i]))
  }
  let o : CompileOutput = { ..base, code, }
  match rehost_round_trip(o) {
    Ok(roundtripped) => {
      assert_eq(roundtripped.length(), 5, msg="往返组数")
      for i = 0; i < 5; i = i + 1 {
        let got = roundtripped[i]
        assert_eq(got.op, ops[i], msg="组 \{i} op 恒等")
        assert_eq(got.operand, operands[i], msg="组 \{i} operand 恒等")
        assert_eq(
          got.loc.line,
          locs[i].line,
          msg="组 \{i} loc.line 侧车重建",
        )
        assert_eq(
          got.loc.column,
          locs[i].column,
          msg="组 \{i} loc.column 侧车重建",
        )
        assert_eq(
          got.loc.file_id,
          locs[i].file_id,
          msg="组 \{i} loc.file_id 侧车重建",
        )
      }
    }
    Err(reason) => fail("往返失败：\{reason}")
  }
}

///|
/// 禁译面拒载锚（Reserved 组在用户 code 内 = 发射失败形态）。
test "rehost_round_trip Reserved 拒载" {
  let base = mk_wasm_output()
  let bad_code : Array[@opcode.Instruction] = [
    @opcode.Instruction::new(
      @opcode.OpCode::Strlen,
      0,
      @source.SourceLoc::new(1, 1),
    ),
  ]
  let o : CompileOutput = { ..base, code: bad_code, }
  match rehost_round_trip(o) {
    Ok(_) => fail("Reserved 组不该往返成功")
    Err(reason) =>
      assert_true(
        reason.contains("emit-failed"),
        msg="emit-failed 形态（实得 \{reason}）",
      )
  }
}
