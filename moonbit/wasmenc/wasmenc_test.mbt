///|
/// wasmenc 黑盒契约（批 1b 收口面）：**A 83 直映 + B 50 组合往返 +
/// C 13 侧车裁决 + D 7 拒载 = 153 全量闸**——「153 条与载体等价性」的
/// 机检账本（A/B 走盲折叠往返、C 走组表引导裁决、D 装载即拒载），
/// 外加 fail loud 拒载 + 歧义实证锚扩全 + 贪心规范化 + 组表核对协议 +
/// 模块段结构往返。
///
/// 往返判据口径（探针 2 同款）：组操作逐项一致（op + operand）；
/// 「非自家发射产物 fail loud」= 字节可被本模板库解释 + 组表侧车逐组
/// 核对双层（探针报告 §2 结论 2 的精确边界）。

///|
/// 测试域 ctx（B 类常量池/装载约定样态——全局基址 0x1000/池/符号尺寸）。
fn tctx() -> @wasmenc.EmitCtx {
  {
    f64_constants: [1.5, -0.25, 0.0],
    i64_constants: [42L, -1L, 0x1122334455667788L],
    argc: 3,
    argv_addr: 0x4000,
    fallthrough_pc: 77,
    host_argv_ptr: 0x5000,
    symbol_sizes: [4, 10, 0],
  }
}

///|
/// A 类全量往返：穷举 opcode 编号空间的全部 Exact 态条目（表驱动同步——
/// 表加条目本测试自动扩面），逐条「发射→折叠→比对」；立即数槽位
/// （PushConst/PushConstF）另带边界值样组。
test "exact_roundtrip_all" {
  let ctx = @wasmenc.EmitCtx::empty()
  let mut exact_n = 0
  for code = 0; code <= 255; code = code + 1 {
    match @opcode.OpCode::from_u8(code) {
      Some(op) => {
        let s = @wasmenc.template_spec(op)
        if s.state is @wasmenc.Exact {
          exact_n = exact_n + 1
          match @wasmenc.emit_group_bytes(op, 0, ctx) {
            Ok(bytes) =>
              match @wasmenc.fold_bytes(bytes, ctx) {
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
  assert_eq(exact_n, 83, msg="A 类计数（与表不变量锚同源）")
}

///|
/// **B 类全量往返（批 1b 收口）**：穷举编号空间的全部 Composed 态条目，
/// 逐条「发射→盲折叠→比对」。operand 样本域分槽型：还原槽（局部偏移/
/// 全局偏移/常量池索引）取非零样值断言还原；无还原槽（Dup/Swap/
/// StepEvent/TrapBounds）operand 折叠为 0 占位——真实 operand 由组表
/// 裁决携带（c_sidecar_adjudication 面）。
test "composed_roundtrip_all" {
  let ctx = tctx()
  let mut composed_n = 0
  for code = 0; code <= 255; code = code + 1 {
    match @opcode.OpCode::from_u8(code) {
      Some(op) => {
        let s = @wasmenc.template_spec(op)
        if s.state is @wasmenc.Composed {
          composed_n = composed_n + 1
          // operand 样本：带还原槽的取非零值（8=局部偏移/全局偏移/池索引
          // 三义域交界的安全值）；TrapBounds 的 -3 覆盖字面量形状
          let operands : Array[Int32] = if op is TrapBounds {
            [0, -3]
          } else if op is PushConstD || op is PushConstQ {
            [0, 1] // 池索引域（池深 3——8 越界属 BadOperand 合法拒载面）
          } else {
            [0, 8]
          }
          for operand in operands {
            match @wasmenc.emit_group_bytes(op, operand, ctx) {
              Ok(bytes) =>
                match @wasmenc.fold_bytes(bytes, ctx) {
                  Ok(groups) => {
                    assert_eq(
                      groups.length(),
                      1,
                      msg="\{op.name()}(\{operand}) 折叠单组",
                    )
                    let g = groups[0]
                    assert_eq(
                      g.op,
                      op,
                      msg="\{op.name()}(\{operand}) 往返 op 一致",
                    )
                    // 还原槽白名单（OpI32/OpBase/池）精确还原；
                    // 其余模板（地址从栈来/operand 不进字节——LoadMem 族/
                    // 算术检查族/Dup/Swap/StepEvent 等）operand=0 占位
                    let want_op = if op is LoadLocal ||
                      op is LoadLocalD ||
                      op is LoadLocalQ ||
                      op is StoreLocal ||
                      op is StoreLocalD ||
                      op is StoreLocalQ ||
                      op is LoadGlobal ||
                      op is LoadGlobalD ||
                      op is LoadGlobalQ ||
                      op is StoreGlobal ||
                      op is StoreGlobalD ||
                      op is StoreGlobalQ ||
                      op is StoreGlobalByte ||
                      op is LoadGlobalByte ||
                      op is LoadGlobalUByte ||
                      op is PushConstD ||
                      op is PushConstQ {
                      operand
                    } else {
                      0
                    }
                    assert_eq(
                      g.operand,
                      want_op,
                      msg="\{op.name()}(\{operand}) 往返 operand（还原槽精确/无槽占位 0）",
                    )
                  }
                  Err(e) => fail("\{op.name()}(\{operand}) 折叠失败")
                }
              Err(e) => fail("\{op.name()}(\{operand}) 发射失败")
            }
          }
        }
      }
      None => ()
    }
  }
  assert_eq(
    composed_n,
    50,
    msg="B 类计数（TruncUByte 入 B——extend8_u 不存在）",
  )
}

///|
/// 立即数槽位边界值往返（PushConst 的 sleb 域 + PushConstF 的位模式域）。
test "slot_operand_boundaries" {
  let ctx = @wasmenc.EmitCtx::empty()
  let consts = [0, 1, -1, 63, 64, -64, -65, 8192, 2147483647, -2147483648]
  for v in consts {
    match @wasmenc.emit_group_bytes(@opcode.PushConst, v, ctx) {
      Ok(bytes) =>
        match @wasmenc.fold_bytes(bytes, ctx) {
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
        match @wasmenc.fold_bytes(bytes, ctx) {
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
/// 混编序列往返（跨族相邻 + 边界立即数——探针 2 [二] 形态；B 类混入）。
test "mixed_sequence_roundtrip" {
  let ctx = tctx()
  let seq1 : Array[(@opcode.OpCode, Int32)] = [
    (@opcode.PushConst, 3),
    (@opcode.PushConst, 4),
    (@opcode.UAdd, 0),
    (@opcode.TruncByte, 0),
    (@opcode.Pop, 0),
  ]
  // B 类混编：局部读 + 溢出检查算术 + 常量池 + 步锚
  let seq2 : Array[(@opcode.OpCode, Int32)] = [
    (@opcode.PushConst, -2147483648),
    (@opcode.PushConst, 1),
    (@opcode.UDiv, 0),
    (@opcode.Not, 0),
    (@opcode.LoadLocal, 12),
    (@opcode.Pop, 0),
    (@opcode.StepEvent, 42),
    (@opcode.Add, 0),
    (@opcode.PushConstD, 1),
    (@opcode.PushConstQ, 2),
    (@opcode.Pop, 0),
    (@opcode.Pop, 0),
    (@opcode.PushConstF, 0x3FC00000),
    (@opcode.Pop, 0),
  ]
  let seqs = [seq1, seq2]
  for i = 0; i < seqs.length(); i = i + 1 {
    match @wasmenc.emit_groups(seqs[i], ctx) {
      Ok(bytes) =>
        match @wasmenc.fold_bytes(bytes, ctx) {
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
              // 无还原槽（StepEvent）operand 占位 0，跳过比对
              if !(seqs[i][k].0 is @opcode.StepEvent) {
                assert_eq(
                  groups[k].operand,
                  seqs[i][k].1,
                  msg="序列\{i + 1}[\{k}] operand",
                )
              }
            }
          }
          Err(e) => fail("序列\{i + 1} 折叠失败")
        }
      Err(e) => fail("序列\{i + 1} 发射失败")
    }
  }
}

///|
/// **贪心最长匹配 = 规范化约定（跨组重叠区）**：[PushConst(255); BitAnd]
/// 两组合的发射字节与 TruncUByte 单组模板字节恒等——盲折叠贪心取长
/// （规范化为 TruncUByte），**组表引导裁决还原真实两分组**。同一字节、
/// 两条路径、两种正确答案——「字节可解释」与「产物身份」分层的活案例。
test "greedy_longest_normalization" {
  let ctx = @wasmenc.EmitCtx::empty()
  let bytes = match
    @wasmenc.emit_groups([(@opcode.PushConst, 255), (@opcode.BitAnd, 0)], ctx) {
    Ok(b) => b
    Err(_) => fail("发射失败")
  }
  // 盲折叠：贪心最长 → 单组 TruncUByte（规范化）
  match @wasmenc.fold_bytes(bytes, ctx) {
    Ok(groups) => {
      assert_eq(groups.length(), 1, msg="盲折叠贪心规范化：单组")
      assert_eq(
        groups[0].op,
        @opcode.TruncUByte,
        msg="贪心最长取 TruncUByte",
      )
    }
    Err(_) => fail("盲折叠应可解释（贪心规范化）")
  }
  // 组表引导裁决：组表声明真实两分组 → 双组还原
  let groups : Array[(@opcode.OpCode, Int32, @source.SourceLoc)] = [
    (@opcode.PushConst, 255, @source.SourceLoc::new(1, 1)),
    (@opcode.BitAnd, 0, @source.SourceLoc::new(1, 5)),
  ]
  match @wasmenc.build_group_table(groups, ctx) {
    Ok((table, _tbytes)) =>
      match @wasmenc.verify_fold_with_table(table, bytes, ctx) {
        Ok(folded) => {
          assert_eq(folded.length(), 2, msg="组表裁决还原两分组")
          assert_eq(folded[0].op, @opcode.PushConst, msg="组 0")
          assert_eq(folded[0].operand, 255, msg="组 0 operand 还原")
          assert_eq(folded[1].op, @opcode.BitAnd, msg="组 1")
        }
        Err(e) => fail("组表裁决应绿")
      }
    Err(_) => fail("组表构建失败")
  }
}

///|
/// **C 类 13 条侧车裁决全量（批 1b 收口核心）**：每条 C 类组「发射 →
/// 组表引导裁决」绿；**歧义对实证**——PushArgc/PushArgv 与 PushConst
/// 同字节、BitNot 与 [PushConst(-1);BitXor] 同字节，同一字节在两组表
/// 下双裁决皆绿（身份=侧车给定）；盲折叠按 A/B 解释（歧义事实锚）。
test "c_sidecar_adjudication" {
  let ctx = tctx()
  // C 类 13 条逐一：发射 → 建表 → 引导裁决绿 → operand 经侧车还原
  let c_ops : Array[(@opcode.OpCode, Int32)] = [
    (@opcode.Jump, 99),
    (@opcode.JumpIfZero, 42),
    (@opcode.JumpIfNotZero, 42),
    (@opcode.Call, 5),
    (@opcode.CallPtr, 5),
    (@opcode.CallVar, 5),
    (@opcode.CallHost, 1007),
    (@opcode.Ret, 0),
    (@opcode.RetVoid, 0),
    (@opcode.BitNot, 0),
    (@opcode.BitNotQ, 0),
    (@opcode.PushArgc, 0),
    (@opcode.PushArgv, 0),
  ]
  for pair in c_ops {
    let (op, operand) = pair
    let groups : Array[(@opcode.OpCode, Int32, @source.SourceLoc)] = [
      (op, operand, @source.SourceLoc::new(1, 1)),
    ]
    match @wasmenc.build_group_table(groups, ctx) {
      Ok((table, bytes)) =>
        match @wasmenc.verify_fold_with_table(table, bytes, ctx) {
          Ok(folded) => {
            assert_eq(folded.length(), 1, msg="\{op.name()} 裁决单组")
            assert_eq(folded[0].op, op, msg="\{op.name()} 侧车身份还原")
            assert_eq(
              folded[0].operand,
              operand,
              msg="\{op.name()} 侧车 operand 还原（operand 不进字节的经侧车）",
            )
          }
          Err(e) => fail("\{op.name()} 侧车裁决应绿")
        }
      Err(e) => fail("\{op.name()} 发射失败")
    }
  }
  // ── 歧义对①：PushArgc vs PushConst(argc)——字节恒等、双组表双裁决 ──
  let argc_bytes = match @wasmenc.emit_group_bytes(@opcode.PushArgc, 0, ctx) {
    Ok(b) => b
    Err(_) => fail("PushArgc 发射失败")
  }
  let pc_bytes = match @wasmenc.emit_group_bytes(@opcode.PushConst, 3, ctx) {
    Ok(b) => b
    Err(_) => fail("PushConst 发射失败")
  }
  assert_eq(
    argc_bytes,
    pc_bytes,
    msg="歧义锚：PushArgc 与 PushConst(argc) 字节恒等",
  )
  // 同一字节：组表说 PushArgc → 裁决 PushArgc；组表说 PushConst → 裁决 PushConst
  let t_argc : Array[(@opcode.OpCode, Int32, @source.SourceLoc)] = [
    (@opcode.PushArgc, 0, @source.SourceLoc::new(1, 1)),
  ]
  match @wasmenc.build_group_table(t_argc, ctx) {
    Ok((table, _)) =>
      match @wasmenc.verify_fold_with_table(table, argc_bytes, ctx) {
        Ok(f) =>
          assert_eq(
            f[0].op,
            @opcode.PushArgc,
            msg="侧车给定身份=PushArgc",
          )
        Err(e) => fail("PushArgc 裁决应绿")
      }
    Err(_) => fail("建表失败")
  }
  let t_pc : Array[(@opcode.OpCode, Int32, @source.SourceLoc)] = [
    (@opcode.PushConst, 3, @source.SourceLoc::new(1, 1)),
  ]
  match @wasmenc.build_group_table(t_pc, ctx) {
    Ok((table, _)) =>
      match @wasmenc.verify_fold_with_table(table, argc_bytes, ctx) {
        Ok(f) =>
          assert_eq(
            f[0].op,
            @opcode.PushConst,
            msg="同字节另裁决=PushConst（身份=侧车给定）",
          )
        Err(e) => fail("PushConst 裁决应绿")
      }
    Err(_) => fail("建表失败")
  }
  // 盲折叠：按 A 类解释（歧义事实锚——C 不入盲表）
  match @wasmenc.fold_bytes(argc_bytes, ctx) {
    Ok(groups) =>
      assert_eq(
        groups[0].op,
        @opcode.PushConst,
        msg="盲折叠按 A/B 解释（PushArgc 不入盲表）",
      )
    Err(_) => fail("盲折叠应可解释（按 PushConst）")
  }
  // ── 歧义对②：PushArgv 同款（argv_addr=0x4000） ──
  let argv_bytes = match @wasmenc.emit_group_bytes(@opcode.PushArgv, 0, ctx) {
    Ok(b) => b
    Err(_) => fail("PushArgv 发射失败")
  }
  let pv_bytes = match
    @wasmenc.emit_group_bytes(@opcode.PushConst, 0x4000, ctx) {
    Ok(b) => b
    Err(_) => fail("PushConst 发射失败")
  }
  assert_eq(
    argv_bytes,
    pv_bytes,
    msg="歧义锚：PushArgv 与 PushConst(argv_addr) 字节恒等",
  )
  // ── 歧义对③：BitNot `41 7f 73`（探针实锤字节序） ──
  let bn_bytes = match @wasmenc.emit_group_bytes(@opcode.BitNot, 0, ctx) {
    Ok(b) => b
    Err(_) => fail("BitNot 发射失败")
  }
  assert_eq(bn_bytes.length(), 3, msg="BitNot 三字节")
  assert_eq(bn_bytes[0], (0x41).to_byte(), msg="[0]=i32.const")
  assert_eq(bn_bytes[1], (0x7F).to_byte(), msg="[1]=-1 sleb")
  assert_eq(bn_bytes[2], (0x73).to_byte(), msg="[2]=i32.xor")
  // 同字节双裁决
  let t_bn : Array[(@opcode.OpCode, Int32, @source.SourceLoc)] = [
    (@opcode.BitNot, 0, @source.SourceLoc::new(1, 1)),
  ]
  match @wasmenc.build_group_table(t_bn, ctx) {
    Ok((table, _)) =>
      match @wasmenc.verify_fold_with_table(table, bn_bytes, ctx) {
        Ok(f) =>
          assert_eq(f[0].op, @opcode.BitNot, msg="侧车给定身份=BitNot")
        Err(e) => fail("BitNot 裁决应绿")
      }
    Err(_) => fail("建表失败")
  }
  let t_pair : Array[(@opcode.OpCode, Int32, @source.SourceLoc)] = [
    (@opcode.PushConst, -1, @source.SourceLoc::new(1, 1)),
    (@opcode.BitXor, 0, @source.SourceLoc::new(2, 1)),
  ]
  match @wasmenc.build_group_table(t_pair, ctx) {
    Ok((table, _)) =>
      match @wasmenc.verify_fold_with_table(table, bn_bytes, ctx) {
        Ok(f) => {
          assert_eq(f.length(), 2, msg="同字节另裁决=两分组")
          assert_eq(f[0].op, @opcode.PushConst, msg="组 0")
          assert_eq(f[1].op, @opcode.BitXor, msg="组 1")
        }
        Err(e) => fail("两分组裁决应绿")
      }
    Err(_) => fail("建表失败")
  }
  // 盲折叠：两分组（批 1a 行为保持——BitNot 不入盲表）
  match @wasmenc.fold_bytes(bn_bytes, ctx) {
    Ok(groups) => {
      assert_eq(
        groups.length(),
        2,
        msg="盲折叠两分组（无 BitNot 模板无歧义）",
      )
      assert_eq(groups[0].op, @opcode.PushConst, msg="组 0")
      assert_eq(groups[1].op, @opcode.BitXor, msg="组 1")
    }
    Err(_) => fail("盲折叠应可解释")
  }
  // ── 歧义对④：BitNotQ（i64 域同款） ──
  let bnq_bytes = match @wasmenc.emit_group_bytes(@opcode.BitNotQ, 0, ctx) {
    Ok(b) => b
    Err(_) => fail("BitNotQ 发射失败")
  }
  let q_pair_bytes = match
    @wasmenc.emit_groups([(@opcode.PushConstQ, 1), (@opcode.BitXorQ, 0)], ctx) {
    Ok(b) => b
    Err(_) => fail("PushConstQ+BitXorQ 发射失败")
  }
  assert_eq(
    bnq_bytes,
    q_pair_bytes,
    msg="歧义锚：BitNotQ 与 [PushConstQ(-1);BitXorQ] 恒等",
  )
  let t_bnq : Array[(@opcode.OpCode, Int32, @source.SourceLoc)] = [
    (@opcode.BitNotQ, 0, @source.SourceLoc::new(1, 1)),
  ]
  match @wasmenc.build_group_table(t_bnq, ctx) {
    Ok((table, _)) =>
      match @wasmenc.verify_fold_with_table(table, bnq_bytes, ctx) {
        Ok(f) => assert_eq(f[0].op, @opcode.BitNotQ, msg="侧车身份=BitNotQ")
        Err(e) => fail("BitNotQ 裁决应绿")
      }
    Err(_) => fail("建表失败")
  }
  // ── JumpIf 正反形状可分（taken 目标槽位镜像） ──
  let jz = match @wasmenc.emit_group_bytes(@opcode.JumpIfZero, 42, ctx) {
    Ok(b) => b
    Err(_) => fail("JumpIfZero 发射失败")
  }
  let jnz = match @wasmenc.emit_group_bytes(@opcode.JumpIfNotZero, 42, ctx) {
    Ok(b) => b
    Err(_) => fail("JumpIfNotZero 发射失败")
  }
  assert_true(
    jz != jnz,
    msg="JumpIfZero 与 JumpIfNotZero 字节形状不同（taken 槽位镜像）",
  )
}

///|
/// fail loud 拒载（探针 2 [三] 形态批 1b 版 + 面外 opcode + 字节偏移口径）。
test "fold_fail_loud_foreign" {
  let ctx = tctx()
  // i64.const 5：池外值（池 [42,-1,0x1122..]）——I64Of 反查失败拒载
  //（池内值 42 可折叠为 PushConstQ(0)——盲折叠可解释性的池依赖面）
  match @wasmenc.fold_bytes([(0x42).to_byte(), (0x05).to_byte()], ctx) {
    Err(@wasmenc.NoTemplate(0)) => ()
    Ok(_) => fail("池外 i64.const 不应折叠（I64Of 池反查失败）")
    Err(_) => fail("i64.const 拒载形态分叉")
  }
  // i32.shl：域检查模板的域内指令单独出现不匹配任何模板
  match @wasmenc.fold_bytes([(0x74).to_byte()], ctx) {
    Err(@wasmenc.NoTemplate(0)) => ()
    Ok(_) => fail("裸 i32.shl 不应折叠（同型未实现序列拒载）")
    Err(_) => fail("i32.shl 拒载形态分叉")
  }
  // 面外 opcode 0xFF
  match @wasmenc.fold_bytes([(0xFF).to_byte()], ctx) {
    Err(@wasmenc.Decode(0, @wasmenc.UnknownOpcode(0xFF))) => ()
    Ok(_) => fail("0xFF 面外指令不应折叠")
    Err(_) => fail("0xFF 拒载形态分叉")
  }
  // 截断的 sleb（探针 SLEB_TRUNCATED 形态）
  match @wasmenc.fold_bytes([(0x41).to_byte(), (0x80).to_byte()], ctx) {
    Err(@wasmenc.Decode(_, @wasmenc.BadOperand(@wasmenc.Truncated))) => ()
    Ok(_) => fail("截断 sleb 不应折叠")
    Err(_) => fail("截断 sleb 拒载形态分叉")
  }
  // **字节偏移口径**（批 1b 改版）：NoTemplate 携带字节偏移非指令索引
  // ——前置 2 字节（PushConst(7)=41 07）后再放一条不可解释指令
  let mixed : Array[Byte] = [
    (0x41).to_byte(),
    (0x07).to_byte(),
    (0x74).to_byte(), // i32.shl 孤立
  ]
  match @wasmenc.fold_bytes(mixed, ctx) {
    Err(@wasmenc.NoTemplate(off)) =>
      assert_eq(
        off,
        2,
        msg="NoTemplate 字节偏移=2（PushConst(7) 占 2 字节后）",
      )
    Ok(_) => fail("孤立 i32.shl 不应折叠")
    Err(_) => fail("形态分叉")
  }
  // 空流：折叠为空序列（合法——模块级闭环的空 code 体形态）
  match @wasmenc.fold_bytes([], ctx) {
    Ok(groups) => assert_eq(groups.length(), 0, msg="空流折叠为空")
    Err(_) => fail("空流不应拒载")
  }
}

///|
/// D 类 7 条发射永久拒载（零发射保留——批 1b 全量账）。
test "emit_fail_loud_reserved" {
  let ctx = tctx()
  for
    op in [
      @opcode.TryBegin,
      @opcode.TryEnd,
      @opcode.Throw,
      @opcode.Strlen,
      @opcode.TrapBoundsVla,
      @opcode.And,
      @opcode.Or,
    ] {
    match @wasmenc.emit_group(op, 0, ctx) {
      Err(@wasmenc.NotImplemented(msg)) =>
        assert_true(
          msg.contains("永久拒载"),
          msg="\{op.name()} D 类永久拒载文案",
        )
      Ok(_) => fail("\{op.name()}（D 类·零发射）不应发射")
      Err(_) => fail("\{op.name()} 拒载形态分叉")
    }
    // 组表引导裁决同样拒载（Reserved 组装载即红）
    let groups : Array[(@opcode.OpCode, Int32, @source.SourceLoc)] = [
      (op, 0, @source.SourceLoc::new(1, 1)),
    ]
    match @wasmenc.build_group_table(groups, ctx) {
      Err(@wasmenc.NotImplemented(_)) => () // 建表即拒
      Ok(_) => fail("\{op.name()} D 类组表构建应拒")
      Err(_) => fail("\{op.name()} 建表拒载形态分叉")
    }
  }
}

///|
/// 组表核对协议（一等公民侧车）：发射侧建表 → 盲折叠核对全绿；篡改字节
//→ GroupMismatch 红（探针 3 [5] 装载核对预演的批 1a 形态——批 1b 带

///|
/// ctx 签名）。
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
      // 盲折叠核对绿
      match @wasmenc.verify_group_table(table, bytes, ctx) {
        Ok(_) => ()
        Err(e) => fail("装载核对应绿")
      }
      // 引导裁决亦绿（A/B 双通道一致）
      match @wasmenc.verify_fold_with_table(table, bytes, ctx) {
        Ok(_) => ()
        Err(e) => fail("引导裁决应绿")
      }
      // 篡改：组 2 的 i32.add（0x6A）改 i32.sub（0x6B）→ 双通道红
      let tampered : Array[Byte] = []
      for b in bytes {
        tampered.push(b)
      }
      assert_eq(
        tampered[4],
        (0x6A).to_byte(),
        msg="组 2 首字节应为 i32.add",
      )
      tampered[4] = (0x6B).to_byte()
      match @wasmenc.verify_group_table(table, tampered, ctx) {
        Ok(_) => fail("篡改字节未检出——盲折叠核对闸无效")
        Err(@wasmenc.GroupMismatch(2, want_op, got_op, _, _)) => {
          assert_eq(want_op, @opcode.UAdd, msg="篡改检出：组表侧 UAdd")
          assert_eq(got_op, @opcode.USub, msg="篡改检出：折叠侧 USub")
        }
        Err(_) => fail("篡改拒载形态分叉")
      }
      match @wasmenc.verify_fold_with_table(table, tampered, ctx) {
        Ok(_) => fail("篡改字节未检出——引导裁决闸无效")
        Err(@wasmenc.TemplateMismatch(2, _, _)) => ()
        Err(_) => fail("引导裁决篡改形态分叉")
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
  assert_eq(bytes[0], (0x00).to_byte(), msg="magic[0]")
  assert_eq(bytes[3], (0x6D).to_byte(), msg="magic[3]='m'")
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
  match @wasmenc.parse_first_code_body(bytes) {
    Ok(got) => {
      let body_bytes : Array[Byte] = []
      for i in got {
        let enc = @wasmenc.winstr_encode(i)
        for b in enc {
          body_bytes.push(b)
        }
      }
      let enc_end = @wasmenc.winstr_encode(@wasmenc.WEnd)
      let body_len = body_bytes.length() - enc_end.length()
      let foldable : Array[Byte] = []
      for i = 0; i < body_len; i = i + 1 {
        foldable.push(body_bytes[i])
      }
      match @wasmenc.fold_bytes(foldable, ctx) {
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
/// **J9 杀阵·①②（黑盒面）**：发射折叠不同步（组表声明与字节不符）+
/// 侧车错配（operand 错）——引导裁决双红实证。③栈序错位（wasm 验证器
/// 不拦类）在 anchors_wbtest 的 mini 栈机面（黑盒访问不到执行器）。
test "j9_table_adjudication_kills" {
  let ctx = tctx()
  // ① 发射折叠不同步：组表声明 LoadLocal(8) 的字节被改写首指令
  //（global.get 1 → local.get 0 的错字节注入）→ 引导裁决 TemplateMismatch
  let groups1 : Array[(@opcode.OpCode, Int32, @source.SourceLoc)] = [
    (@opcode.LoadLocal, 8, @source.SourceLoc::new(1, 1)),
  ]
  match @wasmenc.build_group_table(groups1, ctx) {
    Ok((table, bytes)) => {
      let tampered : Array[Byte] = []
      for b in bytes {
        tampered.push(b)
      }
      // global.get 1 = 23 01 → 改 local.get 0 = 20 00（同长两字节）
      assert_eq(tampered[0], (0x23).to_byte(), msg="首字节 global.get")
      tampered[0] = (0x20).to_byte()
      tampered[1] = (0x00).to_byte()
      match @wasmenc.verify_fold_with_table(table, tampered, ctx) {
        Ok(_) => fail("J9① 失守：错字节未检出")
        Err(@wasmenc.TemplateMismatch(0, _, _)) => () // 红 ✓
        Err(_) => fail("J9① 形态分叉")
      }
      ignore(bytes)
    }
    Err(_) => fail("建表失败")
  }
  // ② 侧车错配：字节是 PushConst(42)，组表 operand 写 43 → 引导裁决
  // GroupMismatch（operand 还原槽比对）
  let groups2 : Array[(@opcode.OpCode, Int32, @source.SourceLoc)] = [
    (@opcode.PushConst, 43, @source.SourceLoc::new(1, 1)),
  ]
  match @wasmenc.build_group_table(groups2, ctx) {
    Ok((table, _)) =>
      // 手工重发射真值 42 的字节（组表 operand 43 是「被改坏的侧车」）
      match @wasmenc.emit_group_bytes(@opcode.PushConst, 42, ctx) {
        Ok(true_bytes) =>
          match @wasmenc.verify_fold_with_table(table, true_bytes, ctx) {
            Ok(_) => fail("J9② 失守：operand 错配未检出")
            Err(@wasmenc.GroupMismatch(0, _, _, 43, 42)) => () // 红 ✓
            Err(_) => fail("J9② 形态分叉")
          }
        Err(_) => fail("重发射失败")
      }
    Err(_) => fail("建表失败")
  }
}
