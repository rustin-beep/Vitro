///|
/// **批 1b wabt 证人 dump**（批 1c wabt CI 闸的消费口——stdout 行前缀
/// DUMP1B 由 D:/tmp/rehost-probe/src/wasmenc_spec_verify_1b.mjs 消费；零孪生：
/// 证「仓内发射字节 = 合法 wasm」的模块字节全部来自本包单源发射器。产物供
/// rehost-probe 的 wasmenc_spec_verify_1b.mjs 消费）：打印 63 条 B/C
/// 模板的发射字节 hex + 垫栈/终态类型（.mjs 据此拼最小模块过
/// wasm-validate——「仓内发射字节 = 合法 wasm」的外部证人，零孪生）。
test "witness_dump_templates_b1b" {
  let ctx : EmitCtx = {
    f64_constants: [1.5, -0.25],
    i64_constants: [42L, -1L],
    argc: 3,
    argv_addr: 0x4000,
    fallthrough_pc: 77,
    host_argv_ptr: 0x5000,
    symbol_sizes: [4, 10],
  }
  // (op, operand, push 垫栈型序（底→顶）, 终态残留深（drop 数）)
  let rows : Array[(@opcode.OpCode, Int32, String, Int32)] = [
    // B 类 50
    (LoadLocal, 8, "", 1),
    (StoreLocal, 8, "i", 0),
    (LoadLocalD, 8, "", 1),
    (StoreLocalD, 8, "d", 0),
    (LoadLocalQ, 8, "", 1),
    (StoreLocalQ, 8, "I", 0),
    (LoadGlobal, 8, "", 1),
    (StoreGlobal, 8, "i", 0),
    (LoadGlobalD, 0, "", 1),
    (StoreGlobalD, 0, "d", 0),
    (LoadGlobalQ, 16, "", 1),
    (StoreGlobalQ, 16, "I", 0),
    (StoreGlobalByte, 0, "i", 0),
    (LoadGlobalByte, 0, "", 1),
    (LoadGlobalUByte, 0, "", 1),
    (GetFrameBase, 0, "", 1),
    (Dup, 0, "i", 2),
    (Swap, 0, "ii", 2),
    (LoadMem, 0, "i", 1),
    (StoreMem, 0, "ii", 0),
    (LoadMemByte, 0, "i", 1),
    (StoreMemByte, 0, "ii", 0),
    (LoadMemUByte, 0, "i", 1),
    (LoadMemD, 0, "i", 1),
    (StoreMemD, 0, "id", 0),
    (LoadMemQ, 0, "i", 1),
    (StoreMemQ, 0, "iI", 0),
    (SplitD, 0, "d", 2),
    (SplitQ, 0, "I", 2),
    (StackAlloc, 0, "i", 1),
    (Memcpy, 0, "iii", 1),
    (Memset, 0, "iIi", 1),
    (Add, 0, "ii", 1),
    (Sub, 0, "ii", 1),
    (Mul, 0, "ii", 1),
    (Neg, 0, "i", 1),
    (NegQ, 0, "I", 1),
    (UNeg, 0, "i", 1),
    (UNegQ, 0, "I", 1),
    (Shl, 0, "ii", 1),
    (Shr, 0, "ii", 1),
    (LShr, 0, "ii", 1),
    (ShlQ, 0, "II", 1),
    (ShrQ, 0, "II", 1),
    (LShrQ, 0, "II", 1),
    (PushConstD, 0, "", 1),
    (PushConstD, 1, "", 1),
    (PushConstQ, 1, "", 1),
    (PushConstQ, 0, "", 1),
    (StepEvent, 0, "", 0),
    (TrapBounds, 0, "i", 1),
    (TrapBounds, -3, "i", 1),
    (TruncUByte, 0, "i", 1),
    // C 类 13
    (Jump, 99, "", 0),
    (JumpIfZero, 42, "i", 0),
    (JumpIfNotZero, 42, "i", 0),
    (Call, 5, "", 0),
    (CallPtr, 5, "i", 0),
    (CallVar, 5, "i", 0),
    (CallHost, 1007, "", 1),
    (Ret, 0, "I", 0),
    (RetVoid, 0, "", 0),
    (BitNot, 0, "i", 1),
    (BitNotQ, 0, "I", 1),
    (PushArgc, 0, "", 1),
    (PushArgv, 0, "", 1),
  ]
  // A 类全量 84 条（批 1c watcheck 全量对拍源——垫栈型 i=I32 I=i64 f=f32
  // d=f64；operand 槽位类取非零样值）
  let a_rows : Array[(@opcode.OpCode, Int32, String, Int32)] = [
    (Nop, 0, "", 0),
    (PushConst, 8, "", 1),
    (Pop, 0, "i", 0),
    (Div, 0, "ii", 1),
    (Mod, 0, "ii", 1),
    (TruncByte, 0, "i", 1),
    (Eq, 0, "ii", 1),
    (Ne, 0, "ii", 1),
    (Lt, 0, "ii", 1),
    (Le, 0, "ii", 1),
    (Gt, 0, "ii", 1),
    (Ge, 0, "ii", 1),
    (Not, 0, "i", 1),
    (ULt, 0, "ii", 1),
    (ULe, 0, "ii", 1),
    (UGt, 0, "ii", 1),
    (UGe, 0, "ii", 1),
    (UDiv, 0, "ii", 1),
    (UMod, 0, "ii", 1),
    (UAdd, 0, "ii", 1),
    (USub, 0, "ii", 1),
    (UMul, 0, "ii", 1),
    (BitAnd, 0, "ii", 1),
    (BitOr, 0, "ii", 1),
    (BitXor, 0, "ii", 1),
    (BitAndQ, 0, "II", 1),
    (BitOrQ, 0, "II", 1),
    (BitXorQ, 0, "II", 1),
    (PushConstF, 0x3FC00000, "", 1),
    (AddF, 0, "ff", 1),
    (SubF, 0, "ff", 1),
    (MulF, 0, "ff", 1),
    (DivF, 0, "ff", 1),
    (NegF, 0, "f", 1),
    (CastI2F, 0, "i", 1),
    (CastF2I, 0, "f", 1),
    (EqF, 0, "ff", 1),
    (NeF, 0, "ff", 1),
    (LtF, 0, "ff", 1),
    (LeF, 0, "ff", 1),
    (GtF, 0, "ff", 1),
    (GeF, 0, "ff", 1),
    (CastU2F, 0, "i", 1),
    (CastUQ2F, 0, "I", 1),
    (AddD, 0, "dd", 1),
    (SubD, 0, "dd", 1),
    (MulD, 0, "dd", 1),
    (DivD, 0, "dd", 1),
    (NegD, 0, "d", 1),
    (CastI2D, 0, "i", 1),
    (CastF2D, 0, "f", 1),
    (CastD2I, 0, "d", 1),
    (CastD2F, 0, "d", 1),
    (EqD, 0, "dd", 1),
    (NeD, 0, "dd", 1),
    (LtD, 0, "dd", 1),
    (LeD, 0, "dd", 1),
    (GtD, 0, "dd", 1),
    (GeD, 0, "dd", 1),
    (CastU2D, 0, "i", 1),
    (CastUQ2D, 0, "I", 1),
    (AddQ, 0, "II", 1),
    (SubQ, 0, "II", 1),
    (MulQ, 0, "II", 1),
    (DivQ, 0, "II", 1),
    (ModQ, 0, "II", 1),
    (CastI2Q, 0, "i", 1),
    (CastQ2I, 0, "I", 1),
    (CastQ2D, 0, "I", 1),
    (CastD2Q, 0, "d", 1),
    (CastD2UQ, 0, "d", 1),
    (EqQ, 0, "II", 1),
    (NeQ, 0, "II", 1),
    (LtQ, 0, "II", 1),
    (LeQ, 0, "II", 1),
    (GtQ, 0, "II", 1),
    (GeQ, 0, "II", 1),
    (CastU2Q, 0, "i", 1),
    (UDivQ, 0, "II", 1),
    (UModQ, 0, "II", 1),
    (ULtQ, 0, "II", 1),
    (ULeQ, 0, "II", 1),
    (UGtQ, 0, "II", 1),
    (UGeQ, 0, "II", 1),
  ]
  let all_rows : Array[(@opcode.OpCode, Int32, String, Int32)] = []
  for row in rows {
    all_rows.push(row)
  }
  for row in a_rows {
    all_rows.push(row)
  }
  for row in all_rows {
    let (op, operand, pushes, drops) = row
    match emit_group_bytes(op, operand, ctx) {
      Ok(bytes) => {
        let hex = bytes_to_hex(bytes)
        println("DUMP1B \{op.name()} \{operand} \{pushes} \{drops} \{hex}")
      }
      Err(_) => println("DUMP1B \{op.name()} EMIT_FAIL")
    }
  }
  // 计数锚（PR #505 审阅 P2-2：dump 行是手写数组——新增 opcode 时四态
  // 计数锚〔anchors_wbtest〕红但**没人被强制补 dump 行**，watcheck 覆盖
  // 对账静默不触发〔批 1b 漏网 Not/UDiv/UMod 的机制根源〕。本锚把
  // 「条目行数 == 三态可发射计数」焊死：新增条目在此红，与 watcheck 的
  // dump→wat 覆盖对账串联成「新增必配 wat」闭环。J9 证红：删任一 a_rows
  // 行即红〔2026-11-13 亲证〕）
  let mut emissive_n = 0
  for code = 0; code <= 255; code = code + 1 {
    match @opcode.OpCode::from_u8(code) {
      Some(op) => {
        let spec = template_spec(op)
        if spec.state is Exact ||
          spec.state is Composed ||
          spec.state is Ambiguous {
          emissive_n = emissive_n + 1
        }
      }
      None => ()
    }
  }
  // 双形态 3 = PushConstD(1)/PushConstQ(0)/TrapBounds(-3)（第二索引/负
  // 字面量形态——同 op 第二行）
  assert_eq(
    all_rows.length(),
    emissive_n + 3,
    msg="dump 行数 == 三态可发射条目（\{emissive_n}）+ 双形态 3——新增 opcode 须连坐补 dump 行与 wat 用例",
  )
}

///|
/// 字节数组 → 两位十六进制串（dump 证人消费）。
fn bytes_to_hex(bytes : Array[Byte]) -> String {
  fn digit(x : UInt32) -> String {
    if x < 10U {
      x.to_string()
    } else if x == 10U {
      "a"
    } else if x == 11U {
      "b"
    } else if x == 12U {
      "c"
    } else if x == 13U {
      "d"
    } else if x == 14U {
      "e"
    } else {
      "f"
    }
  }
  let mut hex = ""
  for b in bytes {
    let v = b.to_uint() & 0xFFU
    hex = hex + digit(v / 16U) + digit(v % 16U)
  }
  hex
}
