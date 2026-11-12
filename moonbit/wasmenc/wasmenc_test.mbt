///|
/// wasmenc 黑盒契约：**A 类 84 条全量往返 + 混编闭环 + fail loud 拒载 +
/// 歧义实证锚 + 组表核对 + 模块段结构往返**（发射器/折叠器对外面的
/// 全部消费形态——包外消费者视角）。
///
/// 往返判据口径（探针 2 同款）：组操作逐项一致（op + operand）；
/// 「非自家发射产物 fail loud」= 字节可被本模板库解释 + 组表侧车逐组
/// 核对双层（探针报告 §2 结论 2 的精确边界）。

///|
/// A 类全量往返：穷举 opcode 编号空间的全部 Exact 态条目（表驱动同步——
/// 表加条目本测试自动扩面），逐条「发射→折叠→比对」；立即数槽位
/// （@opcode.PushConst/@opcode.PushConstF）另带边界值样组。
test "exact_roundtrip_all" {
  let ctx = @wasmenc.EmitCtx::empty()
  let mut exact_n = 0
  for code = 0; code <= 255; code = code + 1 {
    match @opcode.OpCode::from_u8(code) {
      Some(op) => {
        let s = @wasmenc.template_spec(op)
        if s.state is @wasmenc.Exact {
          exact_n = exact_n + 1
          // 无槽位条目用 operand=0；槽位条目走下方样组（此处 0 也要过）
          match @wasmenc.emit_group_bytes(op, 0, ctx) {
            Ok(bytes) =>
              match @wasmenc.fold_bytes(bytes) {
                Ok(groups) => {
                  assert_eq(groups.length(), 1, msg="\{op.name()} 折叠组数")
                  let g = groups[0]
                  assert_eq(g.op, op, msg="\{op.name()} 往返 op 一致")
                  assert_eq(
                    g.operand,
                    0,
                    msg="\{op.name()} 往返 operand 一致",
                  )
                }
                Err(_) =>
                  fail(
                    "\{op.name()} 折叠失败（fail loud 形态见 fold 契约）",
                  )
              }
            Err(_) => fail("\{op.name()} 发射失败")
          }
        }
      }
      None => ()
    }
  }
  assert_eq(
    exact_n,
    84,
    msg="A 类计数（与表不变量锚同源；批 1a 基线 83 + CastD2UQ 随 #485 入表）",
  )
}

///|
/// 立即数槽位边界值往返（@opcode.PushConst 的 sleb 域 + @opcode.PushConstF 的位模式域）。
test "slot_operand_boundaries" {
  let ctx = @wasmenc.EmitCtx::empty()
  let consts = [0, 1, -1, 63, 64, -64, -65, 8192, 2147483647, -2147483648]
  for v in consts {
    match @wasmenc.emit_group_bytes(@opcode.PushConst, v, ctx) {
      Ok(bytes) =>
        match @wasmenc.fold_bytes(bytes) {
          Ok(groups) => {
            assert_eq(
              groups[0].op,
              @opcode.PushConst,
              msg="@opcode.PushConst 往返 op",
            )
            assert_eq(
              groups[0].operand,
              v,
              msg="@opcode.PushConst(\{v}) sleb 域往返",
            )
          }
          Err(_) => fail("@opcode.PushConst 折叠失败")
        }
      Err(_) => fail("@opcode.PushConst 发射失败")
    }
  }
  let f32_operands = [
    0x3FC00000, 0x80000000, 0x7F800000, 0x7FC00000, -2048, 2147483647, -2147483648,
  ]
  for v in f32_operands {
    match @wasmenc.emit_group_bytes(@opcode.PushConstF, v, ctx) {
      Ok(bytes) =>
        match @wasmenc.fold_bytes(bytes) {
          Ok(groups) => {
            assert_eq(
              groups[0].op,
              @opcode.PushConstF,
              msg="@opcode.PushConstF 往返 op",
            )
            assert_eq(
              groups[0].operand,
              v,
              msg="@opcode.PushConstF(0x\{v.reinterpret_as_uint()}) 位模式往返无损",
            )
          }
          Err(_) => fail("@opcode.PushConstF 折叠失败")
        }
      Err(_) => fail("@opcode.PushConstF 发射失败")
    }
  }
}

///|
/// 混编序列往返（跨族相邻 + 边界立即数——探针 2 [二] 形态）。
test "mixed_sequence_roundtrip" {
  let ctx = @wasmenc.EmitCtx::empty()
  let seq1 : Array[(@opcode.OpCode, Int32)] = [
    (@opcode.PushConst, 3),
    (@opcode.PushConst, 4),
    (@opcode.UAdd, 0),
    (@opcode.TruncByte, 0),
    (@opcode.Pop, 0),
  ]
  let seq2 : Array[(@opcode.OpCode, Int32)] = [
    (@opcode.PushConst, -2147483648),
    (@opcode.PushConst, 1),
    (@opcode.UDiv, 0),
    (@opcode.Not, 0),
    (@opcode.PushConstF, 0x3FC00000),
    (@opcode.Pop, 0),
  ]
  let seqs = [seq1, seq2]
  for i = 0; i < seqs.length(); i = i + 1 {
    match @wasmenc.emit_groups(seqs[i], ctx) {
      Ok(bytes) =>
        match @wasmenc.fold_bytes(bytes) {
          Ok(groups) => {
            assert_eq(
              groups.length(),
              seqs[i].length(),
              msg="序列\{i + 1} 折叠组数",
            )
            for k = 0; k < seqs[i].length(); k = k + 1 {
              assert_eq(
                groups[k].op,
                seqs[i][k].0,
                msg="序列\{i + 1}[\{k}] op",
              )
              assert_eq(
                groups[k].operand,
                seqs[i][k].1,
                msg="序列\{i + 1}[\{k}] operand",
              )
            }
          }
          Err(_) => fail("序列\{i + 1} 折叠失败")
        }
      Err(_) => fail("序列\{i + 1} 发射失败")
    }
  }
}

///|
/// fail loud 拒载（探针 2 [三] 四形态 + 面外 opcode）。
test "fold_fail_loud_foreign" {
  // i64.const：面内可解但无 Exact 模板（@opcode.PushConstQ=B 类批 1b）
  match @wasmenc.fold_bytes([(0x42).to_byte(), (0x05).to_byte()]) {
    Err(@wasmenc.NoTemplate(0)) => ()
    Ok(_) => fail("i64.const 不应折叠（B 类未接线面）")
    Err(_) => fail("i64.const 拒载形态分叉")
  }
  // i32.shl：同型未实现指令（@opcode.Shl=B 类域检查模板）
  match @wasmenc.fold_bytes([(0x74).to_byte()]) {
    Err(@wasmenc.NoTemplate(0)) => ()
    Ok(_) => fail("i32.shl 不应折叠（同型未实现指令拒载）")
    Err(_) => fail("i32.shl 拒载形态分叉")
  }
  // 面外 opcode 0xFF
  match @wasmenc.fold_bytes([(0xFF).to_byte()]) {
    Err(@wasmenc.Decode(0, @wasmenc.UnknownOpcode(0xFF))) => ()
    Ok(_) => fail("0xFF 面外指令不应折叠")
    Err(_) => fail("0xFF 拒载形态分叉")
  }
  // 截断的 sleb（探针 SLEB_TRUNCATED 形态）
  match @wasmenc.fold_bytes([(0x41).to_byte(), (0x80).to_byte()]) {
    Err(@wasmenc.Decode(_, @wasmenc.BadOperand(@wasmenc.Truncated))) => ()
    Ok(_) => fail("截断 sleb 不应折叠")
    Err(_) => fail("截断 sleb 拒载形态分叉")
  }
  // 空流：折叠为空序列（合法——模块级闭环的空 code 体形态）
  match @wasmenc.fold_bytes([]) {
    Ok(groups) => assert_eq(groups.length(), 0, msg="空流折叠为空")
    Err(_) => fail("空流不应拒载")
  }
}

///|
/// **歧义对实证锚**（探针 2 [四] 复刻）：`[@opcode.PushConst(-1); @opcode.BitXor]` 的发射
/// 字节与 @opcode.BitNot 的规范模板（[i32.const -1; i32.xor]）字节恒等 `41 7F 73`
/// ——C 类 @opcode.BitNot 批 1b 入表后折叠靠组表侧车裁决，本锚固化字节事实。
test "bitnot_ambiguity_evidence" {
  let ctx = @wasmenc.EmitCtx::empty()
  // 现役 A 类表下的折叠：此序列折叠为 [@opcode.PushConst(-1); @opcode.BitXor]
  let bytes = match
    @wasmenc.emit_groups([(@opcode.PushConst, -1), (@opcode.BitXor, 0)], ctx) {
    Ok(b) => b
    Err(_) => fail("发射失败")
  }
  assert_eq(bytes.length(), 3, msg="三字节序列")
  assert_eq(bytes[0], (0x41).to_byte(), msg="[0]=i32.const")
  assert_eq(bytes[1], (0x7F).to_byte(), msg="[1]=-1 sleb")
  assert_eq(bytes[2], (0x73).to_byte(), msg="[2]=i32.xor")
  match @wasmenc.fold_bytes(bytes) {
    Ok(groups) => {
      assert_eq(
        groups.length(),
        2,
        msg="A 类表下两组折叠（无 @opcode.BitNot 模板无歧义）",
      )
      assert_eq(groups[0].op, @opcode.PushConst, msg="组 0")
      assert_eq(groups[0].operand, -1, msg="组 0 operand")
      assert_eq(groups[1].op, @opcode.BitXor, msg="组 1")
    }
    Err(_) => fail("A 类表下应可折叠")
  }
  // @opcode.BitNot 本体批 1a 拒载（Ambiguous 态显式 fail loud——防误折叠即防歧义）
  match @wasmenc.emit_group(@opcode.BitNot, 0, ctx) {
    Err(@wasmenc.NotImplemented(_)) => ()
    Ok(_) => fail("@opcode.BitNot（歧义态）不应发射——防误折叠")
    Err(_) => fail("@opcode.BitNot 拒载形态分叉")
  }
}

///|
/// B/C/D 态发射 fail loud 的三态文案区分。
test "emit_fail_loud_by_state" {
  let ctx = @wasmenc.EmitCtx::empty()
  // B 类·组合可逆：批 1b 接线提示
  match @wasmenc.emit_group(@opcode.Add, 0, ctx) {
    Err(@wasmenc.NotImplemented(msg)) =>
      assert_true(msg.contains("批 1b"), msg="B 类提示指向批 1b")
    Ok(_) => fail("@opcode.Add（B 类）不应发射")
    Err(_) => fail("@opcode.Add 拒载形态分叉")
  }
  // C 类·歧义需侧车：批 1b/1c + 侧车随行提示
  match @wasmenc.emit_group(@opcode.Jump, 0, ctx) {
    Err(@wasmenc.NotImplemented(msg)) =>
      assert_true(msg.contains("侧车"), msg="C 类提示含侧车")
    Ok(_) => fail("@opcode.Jump（C 类）不应发射")
    Err(_) => fail("@opcode.Jump 拒载形态分叉")
  }
  // D 类·不可映射：永久拒载（@opcode.And 零发射占位——对账修正的机检锚）
  match @wasmenc.emit_group(@opcode.And, 0, ctx) {
    Err(@wasmenc.NotImplemented(msg)) =>
      assert_true(msg.contains("永久拒载"), msg="D 类永久拒载文案")
    Ok(_) => fail("@opcode.And（D 类·零发射占位）不应发射")
    Err(_) => fail("@opcode.And 拒载形态分叉")
  }
  // C 类四态计数锚（黑盒侧可见的最小账目）
  for
    op in [
      @opcode.Jump,
      @opcode.JumpIfZero,
      @opcode.JumpIfNotZero,
      @opcode.Call,
      @opcode.CallPtr,
      @opcode.CallVar,
      @opcode.CallHost,
      @opcode.Ret,
      @opcode.RetVoid,
      @opcode.BitNot,
      @opcode.BitNotQ,
      @opcode.PushArgc,
      @opcode.PushArgv,
    ] {
    match @wasmenc.template_spec(op).state {
      Ambiguous => ()
      _ => fail("\{op.name()} 应标 Ambiguous（歧义需侧车）")
    }
  }
}

///|
/// 组表核对协议（一等公民侧车）：发射侧建表 → 折叠核对全绿；篡改字节
/// → GroupMismatch 红（探针 3 [5] 装载核对预演的批 1a 形态）。
test "grouptable_verify_protocol" {
  let ctx = @wasmenc.EmitCtx::empty()
  let groups : Array[(@opcode.OpCode, Int32, @source.SourceLoc)] = [
    (@opcode.PushConst, 42, @source.SourceLoc::new(1, 1)),
    (@opcode.PushConst, 43, @source.SourceLoc::new(2, 1)),
    (@opcode.UAdd, 0, @source.SourceLoc::new(2, 5)),
    (@opcode.TruncByte, 0, @source.SourceLoc::new(3, 1)),
    (@opcode.PushConstF, 0x3FC00000, @source.SourceLoc::new(4, 1)),
  ]
  match @wasmenc.build_group_table(groups, ctx) {
    Ok((table, bytes)) => {
      assert_eq(table.groups.length(), 5, msg="组表五条")
      assert_eq(table.groups[0].instr_offset, 0, msg="组 0 偏移")
      assert_eq(
        table.groups[1].instr_offset,
        1,
        msg="组 1 偏移（i32.const 42 单字节 sleb）",
      )
      assert_eq(table.groups[4].op, @opcode.PushConstF, msg="组 4 op")
      assert_eq(table.groups[4].loc_line, 4, msg="组 4 loc 携带")
      // 核对绿
      match @wasmenc.verify_group_table(table, bytes) {
        Ok(_) => ()
        Err(_) => fail("装载核对应绿")
      }
      // 篡改：组 2 的 i32.add（0x6A）改 i32.sub（0x6B）→ GroupMismatch(2)
      let tampered : Array[Byte] = []
      for b in bytes {
        tampered.push(b)
      }
      // 定位组 2 字节：组 0/1 各占 2 字节（i32.const = opcode + sleb 立即数，
      // 42/43 的 sleb 均单字节）→ 组 2 的字节偏移 = 4
      assert_eq(
        tampered[4],
        (0x6A).to_byte(),
        msg="组 2 首字节应为 i32.add",
      )
      tampered[4] = (0x6B).to_byte()
      match @wasmenc.verify_group_table(table, tampered) {
        Ok(_) => fail("篡改字节未检出——装载核对闸无效")
        Err(@wasmenc.GroupMismatch(2, want_op, got_op, _, _)) => {
          assert_eq(
            want_op,
            @opcode.UAdd,
            msg="篡改检出：组表侧 @opcode.UAdd",
          )
          assert_eq(
            got_op,
            @opcode.USub,
            msg="篡改检出：折叠侧 @opcode.USub",
          )
        }
        Err(_) => fail("篡改拒载形态分叉")
      }
    }
    Err(_) => fail("组表构建失败")
  }
}

///|
/// 模块段结构往返（模块级闭环）：A 类序列封装最小模块 → code 段解析
/// 提取指令 → 与原序列一致（段编码/解析的机检闭环；wabt 外部验证见
/// 批报告——批 1c 接 CI 闸）。
test "module_roundtrip_minimal" {
  let ctx = @wasmenc.EmitCtx::empty()
  let seq : Array[(@opcode.OpCode, Int32)] = [
    (@opcode.PushConst, 42),
    (@opcode.PushConst, 43),
    (@opcode.UAdd, 0),
    (@opcode.Pop, 0),
  ]
  let instrs : Array[@wasmenc.WInstr] = []
  for pair in seq {
    match @wasmenc.emit_group(pair.0, pair.1, ctx) {
      Ok(g) =>
        for i in g {
          instrs.push(i)
        }
      Err(_) => fail("发射失败")
    }
  }
  let m = @wasmenc.ModuleBuilder::new()
  let t = m.add_type([@wasmenc.WT_I32], [])
  ignore(m.add_memory(16, Some(16)))
  ignore(m.add_global(@wasmenc.WT_I32, true, @wasmenc.WI32Const(0)))
  m.add_export("main", 0, t)
  ignore(m.add_func(t, { locals: [], body: instrs, }))
  let bytes = m.build()
  // magic + 至少 5 段（type/function/memory/global/export/code）
  assert_eq(bytes[0], (0x00).to_byte(), msg="magic[0]")
  assert_eq(bytes[3], (0x6D).to_byte(), msg="magic[3]='m'")
  // 解析：code 段体提取 → 指令序列等值（含尾部自动 end）
  match @wasmenc.parse_first_code_body(bytes) {
    Ok(got) => {
      assert_eq(got.length(), instrs.length() + 1, msg="指令数+end")
      for i = 0; i < instrs.length(); i = i + 1 {
        assert_eq(got[i], instrs[i], msg="指令[\{i}] 往返一致")
      }
      assert_eq(got[got.length() - 1], @wasmenc.WEnd, msg="尾部 end")
    }
    Err(_) => fail("模块解析失败")
  }
  // 歧义实证：探针实锤字节序（41 2A 41 2B 6A 1A）在模块体内可被折叠
  match @wasmenc.parse_first_code_body(bytes) {
    Ok(got) => {
      let body_bytes : Array[Byte] = []
      for i in got {
        // 逐指令重编码为字节流供折叠（解析层→字节层→折叠层的全链闭环）
        let enc = @wasmenc.winstr_encode(i)
        for b in enc {
          body_bytes.push(b)
        }
      }
      // 去 end
      let enc_end = @wasmenc.winstr_encode(@wasmenc.WEnd)
      let body_len = body_bytes.length() - enc_end.length()
      let foldable : Array[Byte] = []
      for i = 0; i < body_len; i = i + 1 {
        foldable.push(body_bytes[i])
      }
      match @wasmenc.fold_bytes(foldable) {
        Ok(groups) => {
          assert_eq(groups.length(), seq.length(), msg="全链折叠组数")
          assert_eq(groups[2].op, @opcode.UAdd, msg="全链折叠组 2")
        }
        Err(_) => fail("全链折叠失败")
      }
    }
    Err(_) => fail("二次解析失败")
  }
}

///|
/// 模块解析边界 fail loud（PR #493 审阅 P2）：两形态修复前静默 Ok——
/// ① sleb 续位跨界（i32.const 立即数续位读 body 外字节，解码"成功"
/// 越过 body 界）；② 缺结尾 end（body 只有 locals 计数，空指令流）。
/// `ModuleParseError::Malformed` 自述覆盖「段内计数与段长不符/结构损坏」，
/// 函数体是 code 段内结构——跨界与缺 end 属同范畴，装载期 fail loud
/// 契约（拒载非自家产物）的边界补齐。红→绿：先于修复入库证红。
test "module_parse_fail_loud_boundary" {
  // 形态 ①：code 段 [id=10, len=6, vec=1, body_size=3, body=00 41 80, 段内尾随 00]
  // —— 0x41 i32.const 的 sleb 续位（0x80）读 body 外的 0x00 才"完整"
  let bad1 : Array[Byte] = [
    (0x00).to_byte(),
    (0x61).to_byte(),
    (0x73).to_byte(),
    (0x6D).to_byte(),
    (0x01).to_byte(),
    (0x00).to_byte(),
    (0x00).to_byte(),
    (0x00).to_byte(),
    (0x0A).to_byte(),
    (0x06).to_byte(),
    (0x01).to_byte(),
    (0x03).to_byte(),
    (0x00).to_byte(),
    (0x41).to_byte(),
    (0x80).to_byte(),
    (0x00).to_byte(),
  ]
  match @wasmenc.parse_first_code_body(bad1) {
    Ok(_) =>
      fail(
        "跨界静默 Ok——sleb 续位越 body 界未检出（fail loud 契约破坏）",
      )
    Err(@wasmenc.Malformed(_)) => ()
    Err(_) => fail("形态分叉：应 Malformed")
  }
  // 形态 ②：code 段 [id=10, len=3, vec=1, body_size=1, body=00]
  // —— 仅 locals 计数字节，指令流为空（合法 wasm 函数体必以 end 收尾）
  let bad2 : Array[Byte] = [
    (0x00).to_byte(),
    (0x61).to_byte(),
    (0x73).to_byte(),
    (0x6D).to_byte(),
    (0x01).to_byte(),
    (0x00).to_byte(),
    (0x00).to_byte(),
    (0x00).to_byte(),
    (0x0A).to_byte(),
    (0x03).to_byte(),
    (0x01).to_byte(),
    (0x01).to_byte(),
    (0x00).to_byte(),
  ]
  match @wasmenc.parse_first_code_body(bad2) {
    Ok(_) =>
      fail(
        "缺 end 静默 Ok——空指令流非合法函数体（fail loud 契约破坏）",
      )
    Err(@wasmenc.Malformed(_)) => ()
    Err(_) => fail("形态分叉：应 Malformed")
  }
}
