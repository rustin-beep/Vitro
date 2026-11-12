///|
/// wasmenc 白盒·**锚点组**：spec 码位锚（wasm 规范外部真值——发射/折叠
/// 共享 WInstr 枚举的自洽盲区防线）+ 表不变量（四态计数 84/50/13/7 与
/// Exact⇔pat——对账账目机检锚；批 1a 基线 83/50/13/7=153，CastD2UQ
/// 随 #485 入 master opcode 表连坐归 A→84/154）+ J9（模板改坏必红
/// 的两路检出实证）+ LEB128 边界（探针坑位 6 复刻）。

///|
/// spec 码位锚：`WInstr` 全部构造器（75）的 wasm 规范字节（含带立即数
/// 指令的全编码——A 类 84 直映 + B 类域内移位族 + 变量/控制流预留面）。
/// 真值源 = wasm MVP / sign-extension-ops / nontrapping-float-to-int
/// conversions（均并入 wasm 2.0 基线）；批 1a 开发期另经探针工程 wabt
/// 全模块外部验证（批报告 §外部证人——本表是仓内 CI 侧的可回归锚）。
test "wasm_opcode_spec_anchor" {
  // 码位真值源：wasm 2.0 基线 + sign-extension-ops（_s 族，i32.extend8_s=0xC0——
  // 批 1a 开发期经探针工程 wabt parseWat→toBinary 编译实证与全模块 validate 双证）
  let cases : Array[(WInstr, Array[Int32])] = [
    // 控制/参数/变量
    (WUnreachable, [0x00]),
    (WNop, [0x01]),
    (WBlock, [0x02, 0x40]),
    (WLoop, [0x03, 0x40]),
    (WEnd, [0x0B]),
    (WBr(1), [0x0C, 0x01]),
    (WBrIf(2), [0x0D, 0x02]),
    (WDrop, [0x1A]),
    (WLocalGet(3), [0x20, 0x03]),
    (WLocalSet(3), [0x21, 0x03]),
    (WLocalTee(3), [0x22, 0x03]),
    (WGlobalGet(3), [0x23, 0x03]),
    (WGlobalSet(3), [0x24, 0x03]),
    // 常量（探针坑位 6：-1 编码 7f；8192 三字节 80 c0 00）
    (WI32Const(-1), [0x41, 0x7F]),
    (WI32Const(8192), [0x41, 0x80, 0xC0, 0x00]),
    (WI64Const(-1), [0x42, 0x7F]),
    // f32.const 1.5（0x3FC00000 小端 00 00 C0 3F）；f64.const 1.5 同位模式
    (
      WF32Const(Float::reinterpret_from_uint(0x3FC00000U)),
      [0x43, 0x00, 0x00, 0xC0, 0x3F],
    ),
    (
      WF64Const(UInt64::reinterpret_as_double(0x3FF8000000000000UL)),
      [0x44, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xF8, 0x3F],
    ),
    // i32 比较（0x45-0x4F）
    (WI32Eqz, [0x45]),
    (WI32Eq, [0x46]),
    (WI32Ne, [0x47]),
    (WI32LtS, [0x48]),
    (WI32LtU, [0x49]),
    (WI32GtS, [0x4A]),
    (WI32GtU, [0x4B]),
    (WI32LeS, [0x4C]),
    (WI32LeU, [0x4D]),
    (WI32GeS, [0x4E]),
    (WI32GeU, [0x4F]),
    // i64 比较（0x51-0x5A）
    (WI64Eq, [0x51]),
    (WI64Ne, [0x52]),
    (WI64LtS, [0x53]),
    (WI64LtU, [0x54]),
    (WI64GtS, [0x55]),
    (WI64GtU, [0x56]),
    (WI64LeS, [0x57]),
    (WI64LeU, [0x58]),
    (WI64GeS, [0x59]),
    (WI64GeU, [0x5A]),
    // f32 比较（0x5B-0x60）
    (WF32Eq, [0x5B]),
    (WF32Ne, [0x5C]),
    (WF32Lt, [0x5D]),
    (WF32Gt, [0x5E]),
    (WF32Le, [0x5F]),
    (WF32Ge, [0x60]),
    // f64 比较（0x61-0x66）
    (WF64Eq, [0x61]),
    (WF64Ne, [0x62]),
    (WF64Lt, [0x63]),
    (WF64Gt, [0x64]),
    (WF64Le, [0x65]),
    (WF64Ge, [0x66]),
    // i32 算术/位（0x6A-0x73）
    (WI32Add, [0x6A]),
    (WI32Sub, [0x6B]),
    (WI32Mul, [0x6C]),
    (WI32DivS, [0x6D]),
    (WI32DivU, [0x6E]),
    (WI32RemS, [0x6F]),
    (WI32RemU, [0x70]),
    (WI32And, [0x71]),
    (WI32Or, [0x72]),
    (WI32Xor, [0x73]),
    // i32 移位族（B 类域内指令——模板批 1b 接线，码位先锚防自洽漂移：
    // 编码解码同改时往返测试不红，仅本表可拦，PR #493 审阅 P3 实锤）
    (WI32Shl, [0x74]),
    (WI32ShrS, [0x75]),
    (WI32ShrU, [0x76]),
    // i64 算术/位（0x7C-0x85）
    (WI64Add, [0x7C]),
    (WI64Sub, [0x7D]),
    (WI64Mul, [0x7E]),
    (WI64DivS, [0x7F]),
    (WI64DivU, [0x80]),
    (WI64RemS, [0x81]),
    (WI64RemU, [0x82]),
    (WI64And, [0x83]),
    (WI64Or, [0x84]),
    (WI64Xor, [0x85]),
    // f32 / f64 算术
    (WF32Neg, [0x8C]),
    (WF32Add, [0x92]),
    (WF32Sub, [0x93]),
    (WF32Mul, [0x94]),
    (WF32Div, [0x95]),
    (WF64Neg, [0x9A]),
    (WF64Add, [0xA0]),
    (WF64Sub, [0xA1]),
    (WF64Mul, [0xA2]),
    (WF64Div, [0xA3]),
    // 转换
    (WI32WrapI64, [0xA7]),
    (WI64ExtendI32S, [0xAC]),
    (WI64ExtendI32U, [0xAD]),
    (WF32ConvertI32S, [0xB2]),
    (WF32ConvertI32U, [0xB3]),
    (WF64ConvertI32S, [0xB7]),
    (WF64ConvertI32U, [0xB8]),
    (WF32DemoteF64, [0xB6]),
    (WF64ConvertI64S, [0xB9]),
    (WF64ConvertI64U, [0xBA]),
    (WF32ConvertI64U, [0xB5]),
    (WF64PromoteF32, [0xBB]),
    (WI32Extend8S, [0xC0]),
    // trunc_sat 前缀族（0xfc + 子码）
    (WI32TruncSatF32S, [0xFC, 0x00]),
    (WI32TruncSatF64S, [0xFC, 0x02]),
    (WI64TruncSatF64S, [0xFC, 0x06]),
    (WI64TruncSatF64U, [0xFC, 0x07]),
    // ── 批 1b 扩面：访存族（opcode + 自然对齐 uleb + 静态 offset=0）──
    (WI32Load, [0x28, 0x02, 0x00]),
    (WI64Load, [0x29, 0x03, 0x00]),
    (WF32Load, [0x2A, 0x02, 0x00]),
    (WF64Load, [0x2B, 0x03, 0x00]),
    (WI32Load8S, [0x2C, 0x00, 0x00]),
    (WI32Load8U, [0x2D, 0x00, 0x00]),
    (WI32Store, [0x36, 0x02, 0x00]),
    (WI64Store, [0x37, 0x03, 0x00]),
    (WF32Store, [0x38, 0x02, 0x00]),
    (WF64Store, [0x39, 0x03, 0x00]),
    (WI32Store8, [0x3A, 0x00, 0x00]),
    // i64 移位（0x86-0x88）+ reinterpret（0xBD）
    (WI64Shl, [0x86]),
    (WI64ShrS, [0x87]),
    (WI64ShrU, [0x88]),
    (WI64ReinterpretF64, [0xBD]),
    // bulk-memory（0xFC + 子码 0x0A/0x0B + 两 memidx 0x00）
    (WMemoryCopy, [0xFC, 0x0A, 0x00, 0x00]),
    (WMemoryFill, [0xFC, 0x0B, 0x00, 0x00]),
    // call（0x10 + uleb——import 0 = env.vitro_host_call 约定）
    (WCall(0), [0x10, 0x00]),
  ]
  for pair in cases {
    let got = winstr_encode(pair.0)
    let want : Array[Byte] = []
    for v in pair.1 {
      want.push(v.to_byte())
    }
    if got != want {
      fail(
        "码位锚失配：编码 \{got.length()} 字节 != spec \{want.length()} 字节（WInstr 码位漂移——往返自洽盲区被锚定）",
      )
    }
    // 编码→解码往返（spec 字节解码回同指令）
    match winstr_decode(want, 0) {
      Ok((instr, n)) => {
        if instr != pair.0 {
          fail("spec 字节解码失配：解出指令与原指令不同")
        }
        if n != want.length() {
          fail("spec 字节消费数失配：\{n} != \{want.length()}")
        }
      }
      Err(_) => fail("spec 字节解码失败")
    }
  }
}

///|
/// 表不变量：四态计数 = 84/50/13/7（对账账目机检锚——漂移即红；批 1a
/// 基线 83/50/13/7〔TruncUByte 移 B 修正值〕+ CastD2UQ 随 #485 入表归 A →
/// 84，与 templates.mbt 头注对账单一致）+
/// `state ≠ Reserved ⇔ pat is Some`（批 1b 版：A/B/C 全带模板——发射/
/// 折叠共享表的完备性；Reserved 零模板）+ 154 闭合（0..156 含空号 47-49）。
test "template_table_invariants" {
  let mut exact_n = 0
  let mut composed_n = 0
  let mut ambiguous_n = 0
  let mut reserved_n = 0
  let mut total = 0
  for code = 0; code <= 255; code = code + 1 {
    match @opcode.OpCode::from_u8(code) {
      Some(op) => {
        total = total + 1
        let s = template_spec(op)
        match s.state {
          Exact => {
            exact_n = exact_n + 1
            match s.pat {
              Some(_) => ()
              None =>
                fail(
                  "\{op.name()} 标 Exact 但 pat=None——表不变量破坏（发射/折叠失同步面）",
                )
            }
          }
          Composed => {
            composed_n = composed_n + 1
            match s.pat {
              Some(_) => ()
              None =>
                fail(
                  "\{op.name()} 标 Composed 但 pat=None——批 1b 起组合模板必须入表",
                )
            }
          }
          Ambiguous => {
            ambiguous_n = ambiguous_n + 1
            match s.pat {
              Some(_) => () // C 类模板仅供组表引导裁决（盲折叠表不含）
              None =>
                fail(
                  "\{op.name()} 标 Ambiguous 但 pat=None——侧车裁决路径无模板可裁",
                )
            }
          }
          Reserved => {
            reserved_n = reserved_n + 1
            match s.pat {
              Some(_) =>
                fail(
                  "\{op.name()} Reserved 却带 pat——零发射保留破约",
                )
              None => ()
            }
          }
        }
      }
      None => ()
    }
  }
  assert_eq(
    total,
    154,
    msg="opcode 编号空间闭合（0..156 含空号 47-49；+CastD2UQ=156 随 #485 入表）",
  )
  assert_eq(
    exact_n,
    84,
    msg="A 类·完全一致计数（批 1a 对账基线 83 + CastD2UQ 归 A——i64.trunc_sat_f64_u 同构直映）",
  )
  assert_eq(
    composed_n,
    50,
    msg="B 类·组合可逆计数（TruncUByte 入 B——extend8_u 不存在）",
  )
  assert_eq(ambiguous_n, 13, msg="C 类·歧义需侧车计数")
  assert_eq(
    reserved_n,
    7,
    msg="D 类·不可映射计数（含 And/Or 零发射占位——对账修正）",
  )
}

///|
/// **盲折叠表形状唯一性**（批 1b 新增）：Exact+Composed 匹配表内不允
/// 许两个模板在任意位置同时最长匹配（同形双模板 = 永久歧义 = 表设计
/// 缺陷——运行期 TableShapeConflict 的静态前置防线）。构造法：对每对
/// 模板，用「形状并集」样本流逐一验证无同长双匹配（发射互射样本 + 交
/// 错拼接）。
test "blind_table_shape_uniqueness" {
  let ctx : EmitCtx = {
    f64_constants: [1.5, -0.25],
    i64_constants: [42L, -1L],
    argc: 3,
    argv_addr: 0x4000,
    fallthrough_pc: 77,
    host_argv_ptr: 0x5000,
    symbol_sizes: [4, 10],
  }
  // 收集 Exact+Composed 全部条目并发射样本字节（operand 样本覆盖还原槽
  // 值域 0/8/255/-1——贪心最长在真实样本流上验证零冲突）
  let samples : Array[Array[Byte]] = []
  let sample_names : Array[String] = []
  for code = 0; code <= 255; code = code + 1 {
    match @opcode.OpCode::from_u8(code) {
      Some(op) => {
        let s = template_spec(op)
        if s.state is Exact || s.state is Composed {
          let operands : Array[Int32] = if op is TrapBounds {
            [0, -3]
          } else {
            [0, 8, 255, -1]
          }
          for operand in operands {
            match emit_group_bytes(op, operand, ctx) {
              Ok(bytes) => {
                samples.push(bytes)
                sample_names.push("\{op.name()}(\{operand})")
              }
              // 池/表越界 operand 合法拒载（样本域内不该发生——除池索引
              // 255 越界：PushConstD/Q 的 255 池外 → BadOperand 合法）
              Err(NotImplemented(_)) =>
                fail("\{op.name()} 模板态不应 NotImplemented")
              Err(BadOperand(_)) => ()
            }
          }
        }
      }
      None => ()
    }
  }
  // 单模板折叠：每样本自折叠零冲突（往返性黑盒已全量锁——此处静态
  // 防线的自样本面）
  for i = 0; i < samples.length(); i = i + 1 {
    match fold_bytes(samples[i], ctx) {
      Ok(_) => ()
      Err(TableShapeConflict(_, a, b)) =>
        fail(
          "形状冲突（自样本 \{sample_names[i]}）：\{a.name()} vs \{b.name()}",
        )
      Err(e) => fail("\{sample_names[i]} 自折叠失败")
    }
  }
  // 拼接双样本面（跨边界贪心最长不产生同长双匹配）：Composed 全量
  //（operand=0 样本）× {Composed 全量 + A 类代表}——O(50×58) 受控
  let pair_samples : Array[Array[Byte]] = []
  let pair_names : Array[String] = []
  for code = 0; code <= 255; code = code + 1 {
    match @opcode.OpCode::from_u8(code) {
      Some(op) => {
        let s = template_spec(op)
        let is_rep = match op {
          PushConst | PushConstF | UAdd | BitXor => s.state is Exact
          _ => false
        }
        if s.state is Composed || is_rep {
          match emit_group_bytes(op, 0, ctx) {
            Ok(bytes) => {
              pair_samples.push(bytes)
              pair_names.push("\{op.name()}")
            }
            Err(_) => ()
          }
        }
      }
      None => ()
    }
  }
  for i = 0; i < pair_samples.length(); i = i + 1 {
    for j = 0; j < pair_samples.length(); j = j + 1 {
      let joined : Array[Byte] = []
      for b in pair_samples[i] {
        joined.push(b)
      }
      for b in pair_samples[j] {
        joined.push(b)
      }
      match fold_bytes(joined, ctx) {
        Ok(_) => () // 贪心确定性解释成功（组数可能 ≠2——跨组重叠规范化）
        Err(TableShapeConflict(_, a, b)) =>
          fail(
            "形状冲突（\{pair_names[i]} + \{pair_names[j]}）：\{a.name()} vs \{b.name()}——盲折叠表存在同形模板",
          )
        Err(_) => () // 拼接边界不可解释（贪心切分失配）——非表缺陷形态
      }
    }
  }
}

///|
/// **J9（改坏模板必红）**：两路检出实证。改坏形态分两类（PR #493 审阅
/// M1/M2' 实测）：改**模板 op 指向**（UAdd 臂发 i32.sub）→ 往返测试红
/// （发射折叠两侧不同步）；改**码位**且编码解码同改（0x6A→0x77）→
/// 往返测试**照样绿**（共享枚举自洽盲区）——该形态仅码位锚可拦
/// （`wasm_opcode_spec_anchor`），防线分立。本用例以「注入错字节」
/// 模拟发射侧模板被改坏的效果（等价攻击面=产物字节），断言①组表核对
/// （发射产物被折叠出不同 op → GroupMismatch 红）与②soft-stack 语义
/// 对拍（发射字节执行 ≠ Vitro 参照语义 → 位不一致红）两道闸都红。
test "j9_tampered_template_detected" {
  let ctx = EmitCtx::empty()
  // ① 组表核对闸：组表声明 UAdd（模板应发 i32.add 0x6A），注入错字节
  // i32.sub（0x6B——「发射模板被改坏」的效果形态）→ 折叠得 USub ≠ 组表
  let table = GroupTable::new()
  table.groups.push({
    gip: 0,
    op: UAdd,
    operand: 0,
    instr_offset: 0,
    instr_len: 1,
    loc_line: 1,
    loc_column: 1,
    loc_file_id: 0,
  })
  let tampered : Array[Byte] = [(0x6B).to_byte()] // i32.sub 冒充 UAdd 产物
  match verify_group_table(table, tampered, ctx) {
    Ok(_) => fail("J9 失守：错字节未检出——组表核对闸无效")
    Err(GroupMismatch(0, want_op, got_op, _, _)) => {
      // 预期红形态：组 0 处 UAdd（组表）vs USub（折叠产物）
      assert_eq(want_op, UAdd, msg="J9 组表侧 op")
      assert_eq(
        got_op,
        USub,
        msg="J9 折叠侧 op（错字节被折叠为 USub）",
      )
    }
    Err(_) => fail("J9 形态分叉：应 GroupMismatch")
  }
  // ② soft-stack 语义闸：同一错字节执行（sub）≠ UAdd 参照语义（加）
  let wasm_out = wasm_run([WI32Sub], [VI32(7), VI32(3)])
  let init_bits : Array[UInt64] = [
    (7 : Int32).to_int64().reinterpret_as_uint64(),
    (3 : Int32).to_int64().reinterpret_as_uint64(),
  ]
  let ref_out = match vitro_ref(UAdd, 0, init_bits) {
    Ok(o) => o
    Err(m) => fail("参照不应 trap：\{m}")
  }
  match wasm_out {
    Ok(out) =>
      // wasm: 7-3=4；参照: 7+3=10——位不一致即「模板改坏被语义闸检出」
      if wval_bits(out[0]) == ref_out[0] {
        fail(
          "J9 失守：错模板执行值与参照一致（选样失误或语义闸无效）",
        )
      }
    Err(_) => fail("样本不应 trap")
  }
}

///|
/// **J9③ 栈序错位（批 1b 新形态——wasm 验证器不拦类）**：StoreMem 的
/// 取数序反转（[addr,value] 错发 [value,addr]）——验证器同型不查、字节
/// 往返自洽；**soft-stack 执行语义闸独检**（错序写错格）+ 引导裁决模板
/// 匹配层双检。
test "j9_stack_order_kill" {
  let ctx = EmitCtx::empty()
  let good = match emit_group(StoreMem, 0, ctx) {
    Ok(i) => i
    Err(_) => fail("StoreMem 发射失败")
  }
  let n = good.length()
  // 模板形状锚：正确取数序 [.., local.get $addr, local.get $val, i32.store]
  assert_eq(
    good[n - 3],
    WLocalGet(L_A),
    msg="倒数第三=取地址（addr 在下）",
  )
  assert_eq(
    good[n - 2],
    WLocalGet(L_V),
    msg="倒数第二=取值（value 在顶）",
  )
  // 构造错序模板（两 get 参数互换——「发射器栈序被改坏」的攻击形态）
  let swapped : Array[WInstr] = []
  for i = 0; i < n; i = i + 1 {
    if i == n - 3 {
      swapped.push(good[n - 2])
    } else if i == n - 2 {
      swapped.push(good[n - 3])
    } else {
      swapped.push(good[i])
    }
  }
  // 语义闸：同一初栈 [addr=0x3000, val=9(顶)]——正确序写 9 到 0x3000；
  // 错序换位写往地址 9（mem[0x3000] 保持 7——值变即红的检出形态）
  let run_case = fn(instrs : Array[WInstr]) -> Int32 raise {
    let mem : Array[Byte] = Array::make(64 * 1024, (0x00).to_byte())
    mem[0x3000] = 7
    mem[0x3004] = 9
    let m = mach_init([], mem, 0L)
    match wasm_exec(instrs, [VI32(0x3000), VI32(9)], m) {
      Ok(_) => m.mem[0x3000].to_int()
      Err(_) => fail("样本不应 trap")
    }
  }
  let good_val = run_case(good)
  let bad_val = run_case(swapped)
  if good_val == bad_val {
    fail("J9③ 样本失效：错序模板执行值与正确序一致")
  }
  if good_val != 9 {
    fail(
      "正确序应写值 9 到 0x3000（得 \{good_val}）——模板栈序自检失败",
    )
  }
  // 裁决闸：错序字节过不了组表引导裁决（模板匹配层检出）
  let table = GroupTable::new()
  table.groups.push({
    gip: 0,
    op: StoreMem,
    operand: 0,
    instr_offset: 0,
    instr_len: n,
    loc_line: 1,
    loc_column: 1,
    loc_file_id: 0,
  })
  let swapped_bytes = winstr_encode_all(swapped)
  match verify_fold_with_table(table, swapped_bytes, ctx) {
    Ok(_) => fail("J9③ 失守：错序字节通过引导裁决")
    Err(TemplateMismatch(0, _, _)) => () // 红 ✓
    Err(_) => fail("J9③ 裁决形态分叉")
  }
  // 对照组：正确序字节裁决绿
  match verify_fold_with_table(table, winstr_encode_all(good), ctx) {
    Ok(_) => ()
    Err(e) => fail("正确序裁决应绿")
  }
}

///|
/// LEB128 边界（探针坑位 6 复刻 + 全域 roundtrip）。
test "leb128_boundaries" {
  // 8192 编码 3 字节（第二字节符号位 0x40 置位必须续写）
  assert_eq(sleb_encode(8192L).length(), 3, msg="8192 sleb 三字节")
  let b = sleb_encode(8192L)
  assert_eq(b[0], (0x80).to_byte(), msg="8192 sleb[0]=80")
  assert_eq(b[1], (0xC0).to_byte(), msg="8192 sleb[1]=c0")
  assert_eq(b[2], (0x00).to_byte(), msg="8192 sleb[2]=00")
  // -1 单字节 7f
  assert_eq(sleb_encode(-1L), [(0x7F).to_byte()], msg="-1 sleb=7f")
  // 截断 fail loud（折叠侧拒载面）
  match sleb_decode([(0x41).to_byte(), (0x80).to_byte()], 1) {
    Err(Truncated) => ()
    Ok(_) => fail("截断 sleb 不应解码成功")
    Err(_) => fail("形态分叉")
  }
  // 值域 roundtrip
  let values = [
    0L, 1L, -1L, 63L, 64L, -64L, -65L, 8192L, 2147483647L, -2147483648L, 9223372036854775807L,
    -9223372036854775808L,
  ]
  for v in values {
    let enc = sleb_encode(v)
    match sleb_decode(enc, 0) {
      Ok((got, n)) => {
        assert_eq(got, v, msg="sleb roundtrip \{v}")
        assert_eq(n, enc.length(), msg="sleb 消费数")
      }
      Err(_) => fail("sleb roundtrip 解码失败：\{v}")
    }
  }
  // uleb 边界
  let uvalues = [
    0UL, 1UL, 127UL, 128UL, 624485UL, 4294967295UL, 18446744073709551615UL,
  ]
  for v in uvalues {
    let enc = uleb_encode(v)
    match uleb_decode(enc, 0) {
      Ok((got, n)) => {
        assert_eq(got, v, msg="uleb roundtrip \{v}")
        assert_eq(n, enc.length(), msg="uleb 消费数")
      }
      Err(_) => fail("uleb roundtrip 解码失败：\{v}")
    }
  }
}

///|
/// f32/f64 位模式小端无损往返（PushConstF 槽位与 f32.const 立即数的
/// 位保真——NaN 位模式作为纯位传递不含运算，payload 确定可比）。
test "float_bit_pattern_roundtrip" {
  let f32_bits = [
    0x3FC00000U, 0x80000000U, 0x7F800000U, 0x7FC00000U, 0xFFFFFFFFU, 0x00000000U,
  ]
  for bits in f32_bits {
    let f = Float::reinterpret_from_uint(bits)
    let enc = winstr_encode(WF32Const(f))
    match winstr_decode(enc, 0) {
      Ok((WF32Const(g), 5)) =>
        assert_eq(
          g.reinterpret_as_uint(),
          bits,
          msg="f32 位模式无损（含 NaN/-0.0/-inf 位）",
        )
      _ => fail("f32.const 编解码形态失配")
    }
  }
  let f64_bits = [
    0x3FF8000000000000UL, 0x8000000000000000UL, 0x7FF0000000000000UL, 0x7FF8000000000000UL,
    0xFFFFFFFFFFFFFFFFUL,
  ]
  for bits in f64_bits {
    let d = UInt64::reinterpret_as_double(bits)
    let enc = winstr_encode(WF64Const(d))
    match winstr_decode(enc, 0) {
      Ok((WF64Const(g), 9)) =>
        assert_eq(
          g.reinterpret_as_uint64(),
          bits,
          msg="f64 位模式无损（含 NaN/-0.0/-inf 位）",
        )
      _ => fail("f64.const 编解码形态失配")
    }
  }
}

///|
/// 组表核对 operand 回归锚（PR #493 审阅 P3·突变 M4 实证：去掉 verify 的
/// operand 比较后 16 用例全绿——零锚）：op 相符而 operand 不符（PushConst
/// 42 的发射字节 vs 组表声明 operand=43）必须 GroupMismatch 拒载。operand
/// 是 C 类侧车消歧的核心判据——批 1b PushArgc/PushConst 歧义对入表后，
/// 此比对若被误删，装载期会把两指令混淆。
test "verify_operand_mismatch_anchor" {
  let table = GroupTable::new()
  table.groups.push({
    gip: 0,
    op: PushConst,
    operand: 43, // 组表声明 43；发射字节实为 42——operand 不符
    instr_offset: 0,
    instr_len: 1,
    loc_line: 1,
    loc_column: 1,
    loc_file_id: 0,
  })
  // PushConst 42 → i32.const 42（sleb 0x2A 单字节；批 1b 起核对携 ctx——
  // I32Slot 槽不依赖常量池，empty 语境等价）
  let bytes = winstr_encode(WI32Const(42))
  match verify_group_table(table, bytes, EmitCtx::empty()) {
    Ok(_) => fail("operand 不符未检出——核对闸缺 operand 比对")
    Err(GroupMismatch(0, _, _, want_operand, got_operand)) => {
      assert_eq(want_operand, 43, msg="组表侧 operand")
      assert_eq(
        got_operand,
        42,
        msg="折叠侧 operand（发射字节真值）",
      )
    }
    Err(_) => fail("形态分叉：应 GroupMismatch")
  }
}
