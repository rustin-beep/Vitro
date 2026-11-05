///|
/// soft-stack 双实现对拍（红线②的机检形态）：mini wasm 栈机（分型域，
/// wasmenc_wbtest.mbt）执行发射序列 vs Vitro 语义直算参照（位模式域，
/// exec_* 臂镜像，本文件）vs 手写期望——三方逐位一致 + 栈效应断言。
/// 探针会话 4 次执行错误全为栈序/错值类（**wasm 验证器不拦**），字节
/// 往返不证明执行语义正确，必须模拟跑。
/// 样本域诚实登记：除法/取模 trap 边界断言**双 trap**（两侧同 trap 面
/// = A 类直映 trap 同构锚）；NaN 参与运算的 payload 非确定面（R2）样本
/// 回避——NaN 仅作位模式传递与饱和转换输入。

// ══════════════ Vitro 语义直算参照（位模式域，exec_* 镜像） ══════════════

///|
/// 位模式域弹 i32（`pop().to_int()`——exec_memory.mbt pop_i32 镜像）。
fn ref_pop_i32(st : Array[UInt64]) -> Result[Int32, String] {
  if st.length() < 1 {
    return Err("下溢")
  }
  Ok(st.remove(st.length() - 1).to_int())
}

///|
/// 位模式域弹 u32 地址（pop_addr 镜像）。
fn ref_pop_u32(st : Array[UInt64]) -> Result[UInt32, String] {
  if st.length() < 1 {
    return Err("下溢")
  }
  Ok(st.remove(st.length() - 1).to_uint())
}

///|
/// 位模式域弹 i64（pop_i64 镜像）。
fn ref_pop_i64(st : Array[UInt64]) -> Result[Int64, String] {
  if st.length() < 1 {
    return Err("下溢")
  }
  Ok(st.remove(st.length() - 1).reinterpret_as_int64())
}

///|
/// 位模式域弹 f32（exec_float 镜像：位模式经低 32 位重解释）。
fn ref_pop_f32(st : Array[UInt64]) -> Result[Float, String] {
  if st.length() < 1 {
    return Err("下溢")
  }
  Ok(Float::reinterpret_from_uint(st.remove(st.length() - 1).to_uint()))
}

///|
/// 位模式域弹 f64。
fn ref_pop_f64(st : Array[UInt64]) -> Result[Double, String] {
  if st.length() < 1 {
    return Err("下溢")
  }
  Ok(UInt64::reinterpret_as_double(st.remove(st.length() - 1)))
}

///|
/// i32 语义值符号扩展压栈（push_i32 镜像——trap.mbt:44 亲读：负值符号
/// 扩展，非零扩展）。
fn ref_push_i32(st : Array[UInt64], v : Int32) -> Unit {
  st.push(v.to_int64().reinterpret_as_uint64())
}

///|
/// 参照主入口：op + 初始位模式栈 → 终态位模式栈 / Err（=trap 面）。
/// **与 wasm_run 独立**：位模式域 u64 直算（exec_arith / exec_float /
/// exec_memory 臂镜像）；饱和转换用内建 to_int / to_int64（mini 机侧是
/// 手写 sat_*——双实现对拍锚）。
fn vitro_ref(
  op : @opcode.OpCode,
  operand : Int32,
  init : Array[UInt64],
) -> Result[Array[UInt64], String] {
  let st : Array[UInt64] = []
  for v in init {
    st.push(v)
  }
  fn pop2i32(st : Array[UInt64]) -> Result[(Int32, Int32), String] {
    if st.length() < 2 {
      return Err("下溢")
    }
    let b = st.remove(st.length() - 1).to_int()
    let a = st.remove(st.length() - 1).to_int()
    Ok((a, b))
  }
  fn pushBool(st : Array[UInt64], r : Bool) -> Unit {
    st.push(if r { 1UL } else { 0UL })
  }
  match op {
    Nop => ()
    PushConst => ref_push_i32(st, operand)
    Pop =>
      if st.length() < 1 {
        return Err("下溢")
      } else {
        ignore(st.remove(st.length() - 1))
      }
    Div => {
      let (a, b) = match pop2i32(st) {
        Ok(p) => p
        Err(e) => return Err(e)
      }
      if b == 0 {
        return Err("整数除法溢出（除零）")
      }
      if a == -2147483648 && b == -1 {
        return Err("整数除法溢出（INT_MIN/-1）")
      }
      ref_push_i32(st, a / b)
    }
    Mod => {
      let (a, b) = match pop2i32(st) {
        Ok(p) => p
        Err(e) => return Err(e)
      }
      if b == 0 {
        return Err("整数取模溢出（除零）")
      }
      if a == -2147483648 && b == -1 {
        return Err("整数取模溢出（INT_MIN/-1）")
      }
      ref_push_i32(st, a % b)
    }
    UAdd | USub | UMul | BitAnd | BitOr | BitXor => {
      let (a, b) = match pop2i32(st) {
        Ok(p) => p
        Err(e) => return Err(e)
      }
      let r = match op {
        UAdd => a + b
        USub => a - b
        UMul => a * b
        BitAnd => a & b
        BitOr => a | b
        _ => a ^ b
      }
      ref_push_i32(st, r) // MoonBit Int32 回绕（F1）；i32 语义符号扩展压栈
    }
    UDiv | UMod => {
      let b = match ref_pop_u32(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let a = match ref_pop_u32(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      if b == 0U {
        return Err("无符号除零")
      }
      st.push((if op is UDiv { a / b } else { a % b }).to_uint64())
    }
    TruncByte => {
      let a = match ref_pop_i32(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let b = a & 0xFF
      ref_push_i32(st, if b >= 128 { b - 256 } else { b })
    }
    Eq | Ne | Lt | Le | Gt | Ge | ULt | ULe | UGt | UGe => {
      let b = match ref_pop_u32(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let a = match ref_pop_u32(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      // 位模式比较域：有符号族经 u32 位模式回 i32 符号解释（exec_arith
      // arith_i32 镜像）；无符号族直接 u32 域比较（arith_u32 镜像）
      let r : Bool = match op {
        Eq => a == b
        Ne => a != b
        Lt => a.reinterpret_as_int() < b.reinterpret_as_int()
        Le => a.reinterpret_as_int() <= b.reinterpret_as_int()
        Gt => a.reinterpret_as_int() > b.reinterpret_as_int()
        Ge => a.reinterpret_as_int() >= b.reinterpret_as_int()
        ULt => a < b
        ULe => a <= b
        UGt => a > b
        _ => a >= b
      }
      pushBool(st, r)
    }
    Not => {
      let a = match ref_pop_i32(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      st.push(if a != 0 { 0UL } else { 1UL })
    }
    BitAndQ | BitOrQ | BitXorQ | AddQ | SubQ | MulQ => {
      if st.length() < 2 {
        return Err("下溢")
      }
      let b = st.remove(st.length() - 1).reinterpret_as_int64()
      let a = st.remove(st.length() - 1).reinterpret_as_int64()
      let r = match op {
        BitAndQ => a & b
        BitOrQ => a | b
        BitXorQ => a ^ b
        AddQ => a + b
        SubQ => a - b
        _ => a * b
      }
      st.push(r.reinterpret_as_uint64()) // Q 族回绕（exec_float 镜像）
    }
    DivQ | ModQ => {
      if st.length() < 2 {
        return Err("下溢")
      }
      let b = st.remove(st.length() - 1).reinterpret_as_int64()
      let a = st.remove(st.length() - 1).reinterpret_as_int64()
      if b == 0L {
        return Err("long long 除零")
      }
      if a == -9223372036854775808L && b == -1L {
        return Err("long long 溢出（LLONG_MIN/-1）")
      }
      st.push((if op is DivQ { a / b } else { a % b }).reinterpret_as_uint64())
    }
    UDivQ | UModQ => {
      if st.length() < 2 {
        return Err("下溢")
      }
      let b = st.remove(st.length() - 1)
      let a = st.remove(st.length() - 1)
      if b == 0UL {
        return Err("u64 除零")
      }
      st.push(if op is UDivQ { a / b } else { a % b })
    }
    EqQ | NeQ | LtQ | LeQ | GtQ | GeQ => {
      if st.length() < 2 {
        return Err("下溢")
      }
      let b = st.remove(st.length() - 1).reinterpret_as_int64()
      let a = st.remove(st.length() - 1).reinterpret_as_int64()
      let r : Bool = match op {
        EqQ => a == b
        NeQ => a != b
        LtQ => a < b
        LeQ => a <= b
        GtQ => a > b
        _ => a >= b
      }
      pushBool(st, r)
    }
    ULtQ | ULeQ | UGtQ | UGeQ => {
      if st.length() < 2 {
        return Err("下溢")
      }
      let b = st.remove(st.length() - 1)
      let a = st.remove(st.length() - 1)
      let r : Bool = match op {
        ULtQ => a < b
        ULeQ => a <= b
        UGtQ => a > b
        _ => a >= b
      }
      pushBool(st, r)
    }
    PushConstF => st.push(operand.reinterpret_as_uint().to_uint64())
    AddF | SubF | MulF | DivF => {
      if st.length() < 2 {
        return Err("下溢")
      }
      let b = Float::reinterpret_from_uint(st.remove(st.length() - 1).to_uint())
      let a = Float::reinterpret_from_uint(st.remove(st.length() - 1).to_uint())
      let r = match op {
        AddF => a + b
        SubF => a - b
        MulF => a * b
        _ => a / b // IEEE：除零=±inf/NaN（#163）
      }
      st.push(Float::reinterpret_as_uint(r).to_uint64())
    }
    NegF => {
      let a = match ref_pop_f32(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      st.push(Float::reinterpret_as_uint(-a).to_uint64())
    }
    EqF | NeF | LtF | LeF | GtF | GeF => {
      if st.length() < 2 {
        return Err("下溢")
      }
      let b = Float::reinterpret_from_uint(st.remove(st.length() - 1).to_uint())
      let a = Float::reinterpret_from_uint(st.remove(st.length() - 1).to_uint())
      let r : Bool = match op {
        EqF => a == b
        NeF => a != b
        LtF => a < b
        LeF => a <= b
        GtF => a > b
        _ => a >= b
      }
      pushBool(st, r)
    }
    CastI2F => {
      let a = match ref_pop_i32(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      st.push(
        Float::reinterpret_as_uint(Float::from_double(a.to_double())).to_uint64(),
      )
    }
    CastU2F => {
      let a = match ref_pop_u32(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      st.push(
        Float::reinterpret_as_uint(Float::from_double(a.to_double())).to_uint64(),
      )
    }
    CastUQ2F => {
      let a = match ref_pop_i64(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      st.push(
        Float::reinterpret_as_uint(
          Float::from_double(a.reinterpret_as_uint64().to_double()),
        ).to_uint64(),
      )
    }
    CastF2I => {
      let a = match ref_pop_f32(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      ref_push_i32(st, a.to_int()) // 内建饱和（exec_float.mbt:101 同款）
    }
    AddD | SubD | MulD | DivD => {
      if st.length() < 2 {
        return Err("下溢")
      }
      let b = UInt64::reinterpret_as_double(st.remove(st.length() - 1))
      let a = UInt64::reinterpret_as_double(st.remove(st.length() - 1))
      let r = match op {
        AddD => a + b
        SubD => a - b
        MulD => a * b
        _ => a / b
      }
      st.push(r.reinterpret_as_uint64())
    }
    NegD => {
      let a = match ref_pop_f64(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      st.push((-a).reinterpret_as_uint64())
    }
    EqD | NeD | LtD | LeD | GtD | GeD => {
      if st.length() < 2 {
        return Err("下溢")
      }
      let b = UInt64::reinterpret_as_double(st.remove(st.length() - 1))
      let a = UInt64::reinterpret_as_double(st.remove(st.length() - 1))
      let r : Bool = match op {
        EqD => a == b
        NeD => a != b
        LtD => a < b
        LeD => a <= b
        GtD => a > b
        _ => a >= b
      }
      pushBool(st, r)
    }
    CastI2D => {
      let a = match ref_pop_i32(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      st.push(a.to_double().reinterpret_as_uint64())
    }
    CastU2D => {
      let a = match ref_pop_u32(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      st.push(a.to_double().reinterpret_as_uint64())
    }
    CastUQ2D => {
      let a = match ref_pop_i64(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      st.push(a.reinterpret_as_uint64().to_double().reinterpret_as_uint64())
    }
    CastF2D => {
      let a = match ref_pop_f32(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      st.push(a.to_double().reinterpret_as_uint64())
    }
    CastD2F => {
      let a = match ref_pop_f64(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      st.push(Float::reinterpret_as_uint(Float::from_double(a)).to_uint64())
    }
    CastD2I => {
      let a = match ref_pop_f64(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      ref_push_i32(st, a.to_int()) // 内建饱和
    }
    CastI2Q => {
      let a = match ref_pop_i32(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      st.push(a.to_int64().reinterpret_as_uint64())
    }
    CastU2Q => {
      let a = match ref_pop_u32(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      st.push(a.to_uint64())
    }
    CastQ2I => {
      let a = match ref_pop_i64(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      ref_push_i32(st, a.to_int()) // 低 32 位截断
    }
    CastQ2D => {
      let a = match ref_pop_i64(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      st.push(a.to_double().reinterpret_as_uint64())
    }
    CastD2Q => {
      let a = match ref_pop_f64(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      st.push(a.to_int64().reinterpret_as_uint64()) // 内建饱和
    }
    CastD2UQ => {
      let a = match ref_pop_f64(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      st.push(a.to_uint64()) // #471 饱和无符号（vm exec_float.mbt 同款内建）
    }
    _ =>
      return Err(
        "参照未覆盖 op=\{op.name()}（批 1a soft-stack 面外）",
      )
  }
  Ok(st)
}

// ══════════════ 断言器 ══════════════

///|
/// 三方一致断言器：发射 → mini wasm 机（分型域）vs Vitro 参照（位模式域）
/// vs 手写期望——逐位比对 + **栈效应断言**（净深差 = spec.pushes-pops）。
/// trap 面：两侧同 trap 才绿（除法边界 = A 类直映 trap 同构锚）。
fn expect_sem(
  op : @opcode.OpCode,
  operand : Int32,
  ins : Array[WVal],
  want : Array[WVal],
) -> Unit raise {
  let instrs = match emit_group(op, operand, EmitCtx::empty()) {
    Ok(i) => i
    Err(_) => fail("emit \{op.name()} 失败（Exact 态不应失败）")
  }
  let want_bits : Array[UInt64] = []
  for w in want {
    want_bits.push(wval_bits(w))
  }
  let init_bits : Array[UInt64] = []
  for v in ins {
    init_bits.push(wval_bits(v))
  }
  let ref_out = match vitro_ref(op, operand, init_bits) {
    Ok(out) => out
    Err(msg) =>
      // 参照 trap → wasm 机必须也 trap（trap 面同构断言）
      match wasm_run(instrs, ins) {
        Ok(_) =>
          fail(
            "\{op.name()}: 参照 trap（\{msg}）但 wasm 机未 trap——trap 面不同构",
          )
        Err(Trap(_)) => return // 双 trap ✓（trap 形态显式——栈错不算双 trap）
        Err(Underflow) =>
          fail(
            "\{op.name()}: 参照 trap 但 wasm 机下溢——栈序破坏非 trap 同构",
          )
        Err(TypeError) =>
          fail(
            "\{op.name()}: 参照 trap 但 wasm 机类型错——模板类型序破坏",
          )
      }
  }
  let wasm_out = match wasm_run(instrs, ins) {
    Ok(out) => out
    Err(_) =>
      fail(
        "\{op.name()}: wasm 机 trap/栈错但参照成功——trap 面不同构或栈序破坏",
      )
  }
  // 栈效应不变量（模板表声明 vs 两侧实测净深差——红线②的静态面）
  let s = template_spec(op)
  if s.pops >= 0 {
    let delta = wasm_out.length() - ins.length()
    if delta != s.pushes - s.pops {
      fail(
        "\{op.name()}: wasm 栈净差 \{delta} != 表声明 \{s.pushes - s.pops}",
      )
    }
    let ref_delta = ref_out.length() - init_bits.length()
    if ref_delta != s.pushes - s.pops {
      fail(
        "\{op.name()}: 参照栈净差 \{ref_delta} != 表声明 \{s.pushes - s.pops}",
      )
    }
  }
  if wasm_out.length() != want_bits.length() {
    fail(
      "\{op.name()}: wasm 出栈深 \{wasm_out.length()} != 期望 \{want_bits.length()}",
    )
  }
  for i = 0; i < want_bits.length(); i = i + 1 {
    let got = wval_bits(wasm_out[i])
    if got != want_bits[i] {
      fail(
        "\{op.name()}[\{i}]: wasm 机 = \{got} != 期望 \{want_bits[i]}（mini 栈机语义红）",
      )
    }
    if ref_out[i] != want_bits[i] {
      fail(
        "\{op.name()}[\{i}]: 参照 = \{ref_out[i]} != 期望 \{want_bits[i]}（Vitro 直算红）",
      )
    }
  }
}

// ══════════════ 样本（A 类 84 条逐条 expect_sem 全覆盖——含回绕/饱和/
// trap 边界与 PushConst 槽位形态；PR #493 审阅 P3 勘正：原注「单指令样本
// 46 + 槽位 3 + 其余经混合臂」与实测覆盖不符；+CastD2UQ 随 #485 入表） ══════════════

///|
/// i32 / U 系 / 位运算族（回绕与符号扩展边界全带；除法 trap 双断言）。
test "softstack_i32_family" {
  expect_sem(Nop, 0, [VI32(5)], [VI32(5)])
  expect_sem(PushConst, 42, [], [VI32(42)])
  expect_sem(PushConst, -1, [], [VI32(-1)])
  expect_sem(PushConst, -2147483648, [], [VI32(-2147483648)])
  expect_sem(Pop, 0, [VI32(9)], [])
  expect_sem(UAdd, 0, [VI32(7), VI32(3)], [VI32(10)])
  expect_sem(UAdd, 0, [VI32(2147483647), VI32(1)], [VI32(-2147483648)]) // 回绕
  expect_sem(USub, 0, [VI32(7), VI32(3)], [VI32(4)])
  expect_sem(USub, 0, [VI32(0), VI32(1)], [VI32(-1)])
  expect_sem(UMul, 0, [VI32(65536), VI32(65536)], [VI32(0)]) // 2^32 回绕
  expect_sem(UMul, 0, [VI32(65536), VI32(65537)], [VI32(65536 * 65537)])
  expect_sem(Div, 0, [VI32(7), VI32(3)], [VI32(2)])
  expect_sem(Div, 0, [VI32(-7), VI32(2)], [VI32(-3)]) // C 截断向零
  expect_sem(Div, 0, [VI32(-2147483648), VI32(-1)], []) // 双 trap
  expect_sem(Div, 0, [VI32(7), VI32(0)], [])
  expect_sem(Mod, 0, [VI32(7), VI32(3)], [VI32(1)])
  expect_sem(Mod, 0, [VI32(-7), VI32(2)], [VI32(-1)])
  expect_sem(Mod, 0, [VI32(7), VI32(0)], [])
  expect_sem(UDiv, 0, [VI32(-1), VI32(2)], [VI32(2147483647)]) // 0xFFFFFFFF/2
  expect_sem(UDiv, 0, [VI32(7), VI32(0)], [])
  expect_sem(UMod, 0, [VI32(-1), VI32(16)], [VI32(15)])
  expect_sem(UMod, 0, [VI32(7), VI32(0)], [])
  expect_sem(TruncByte, 0, [VI32(200)], [VI32(-56)]) // 病 33：char c=200 读回 -56
  expect_sem(TruncByte, 0, [VI32(127)], [VI32(127)])
  expect_sem(Eq, 0, [VI32(7), VI32(3)], [VI32(0)])
  expect_sem(Eq, 0, [VI32(3), VI32(3)], [VI32(1)])
  expect_sem(Ne, 0, [VI32(7), VI32(3)], [VI32(1)])
  expect_sem(Lt, 0, [VI32(-7), VI32(3)], [VI32(1)]) // 有符号域
  expect_sem(Le, 0, [VI32(3), VI32(3)], [VI32(1)])
  expect_sem(Gt, 0, [VI32(-7), VI32(3)], [VI32(0)])
  expect_sem(Ge, 0, [VI32(7), VI32(3)], [VI32(1)])
  expect_sem(Not, 0, [VI32(0)], [VI32(1)])
  expect_sem(Not, 0, [VI32(5)], [VI32(0)])
  expect_sem(ULt, 0, [VI32(1), VI32(-1)], [VI32(1)]) // a=1, b=0xFF..F → 1 <u max // 无符号域
  expect_sem(ULe, 0, [VI32(1), VI32(1)], [VI32(1)])
  expect_sem(UGt, 0, [VI32(-1), VI32(1)], [VI32(1)])
  expect_sem(UGe, 0, [VI32(-1), VI32(1)], [VI32(1)])
  expect_sem(BitAnd, 0, [VI32(-25776), VI32(4080)], [VI32(-25776 & 4080)])
  expect_sem(BitOr, 0, [VI32(-25776), VI32(4080)], [VI32(-25776 | 4080)])
  expect_sem(BitXor, 0, [VI32(-25776), VI32(4080)], [VI32(-25776 ^ 4080)])
}

///|
/// Q 族（回绕/无符号对偶/饱和转换边界）。
test "softstack_q_family" {
  expect_sem(AddQ, 0, [VI64(1), VI64(2)], [VI64(3)])
  expect_sem(AddQ, 0, [VI64(9223372036854775807), VI64(1)], [
    VI64(-9223372036854775808),
  ]) // 回绕不 trap（对账修正锚）
  expect_sem(SubQ, 0, [VI64(-9223372036854775808), VI64(1)], [
    VI64(9223372036854775807),
  ])
  expect_sem(MulQ, 0, [VI64(4294967296), VI64(4294967296)], [VI64(0)])
  expect_sem(DivQ, 0, [VI64(-7), VI64(2)], [VI64(-3)])
  expect_sem(DivQ, 0, [VI64(-9223372036854775808), VI64(-1)], []) // 双 trap
  expect_sem(DivQ, 0, [VI64(7), VI64(0)], [])
  expect_sem(ModQ, 0, [VI64(-7), VI64(2)], [VI64(-1)])
  expect_sem(ModQ, 0, [VI64(7), VI64(0)], [])
  expect_sem(UDivQ, 0, [VI64(-1), VI64(2)], [VI64(9223372036854775807)])
  expect_sem(UDivQ, 0, [VI64(7), VI64(0)], [])
  expect_sem(UModQ, 0, [VI64(-1), VI64(16)], [VI64(15)])
  expect_sem(UModQ, 0, [VI64(7), VI64(0)], [])
  expect_sem(EqQ, 0, [VI64(7), VI64(3)], [VI32(0)])
  expect_sem(NeQ, 0, [VI64(7), VI64(3)], [VI32(1)])
  expect_sem(LtQ, 0, [VI64(-7), VI64(3)], [VI32(1)])
  expect_sem(LeQ, 0, [VI64(3), VI64(3)], [VI32(1)])
  expect_sem(GtQ, 0, [VI64(-7), VI64(3)], [VI32(0)])
  expect_sem(GeQ, 0, [VI64(7), VI64(3)], [VI32(1)])
  expect_sem(ULtQ, 0, [VI64(1), VI64(-1)], [VI32(1)]) // a=1, b=max → 1 <u max（病 34 对偶）
  expect_sem(ULeQ, 0, [VI64(1), VI64(1)], [VI32(1)])
  expect_sem(UGtQ, 0, [VI64(-1), VI64(1)], [VI32(1)])
  expect_sem(UGeQ, 0, [VI64(-1), VI64(1)], [VI32(1)])
  expect_sem(BitAndQ, 0, [VI64(-1), VI64(0xFF)], [VI64(255)])
  expect_sem(BitOrQ, 0, [VI64(-256), VI64(0xFF)], [VI64(-1)])
  expect_sem(BitXorQ, 0, [VI64(-1), VI64(0xFF)], [VI64(-256)])
  expect_sem(CastI2Q, 0, [VI32(-5)], [VI64(-5)]) // 符号扩展
  expect_sem(CastU2Q, 0, [VI32(-5)], [VI64(4294967291)]) // u32 零扩展（病 31）
  expect_sem(CastQ2I, 0, [VI64(-5)], [VI32(-5)])
  expect_sem(CastQ2I, 0, [VI64(4294967296 + 7)], [VI32(7)]) // 低 32 位截断
  expect_sem(CastQ2D, 0, [VI64(-7)], [VF64(-7.0)])
  expect_sem(CastD2Q, 0, [VF64(2.7)], [VI64(2)])
  expect_sem(
    CastD2Q,
    0,
    [VF64(UInt64::reinterpret_as_double(0x7FF8000000000000UL))],
    [VI64(0)],
  ) // NaN→0 饱和
  expect_sem(
    CastD2Q,
    0,
    [VF64(UInt64::reinterpret_as_double(0x7E37E43C8800759CUL))],
    [VI64(9223372036854775807)],
  ) // 上界饱和
  // CastD2UQ（#471 饱和无符号——i64.trunc_sat_f64_u 直映；随 #485 入表）
  expect_sem(CastD2UQ, 0, [VF64(2.7)], [VI64(2)])
  expect_sem(
    CastD2UQ,
    0,
    [VF64(UInt64::reinterpret_as_double(0x7FF8000000000000UL))],
    [VI64(0)],
  ) // NaN→0
  expect_sem(CastD2UQ, 0, [VF64(-1.5)], [VI64(0)]) // 负值→0
  expect_sem(CastD2UQ, 0, [VF64(9223372036854775808.0)], [
    VI64(-9223372036854775808L),
  ]) // #471 病灶段 [2^63,2^64) 无损（位模式 0x8000...=Int64 最小值；CastD2Q 在此段饱和 INT64_MAX 即旧病灶）
  expect_sem(CastD2UQ, 0, [VF64(18446744073709551616.0)], [VI64(-1L)]) // ≥2^64→MAX（0xFFFFFFFFFFFFFFFF 位模式 = -1）
}

///|
/// f32/f64 族（IEEE 边界：除零 inf 位、-0.0 位保真、饱和截断、无符号
/// 转换；inf/-0.0 位模式字面锚定——非 NaN payload 面，确定可比）。
test "softstack_float_family" {
  expect_sem(PushConstF, 0x3FC00000, [], [VF32(1.5)]) // 1.5f 位模式
  expect_sem(PushConstF, -2048, [], [
    VF32(Float::reinterpret_from_uint((-2048).reinterpret_as_uint())),
  ]) // 任意位模式（负 operand=0xFFFFF800）无损往返
  expect_sem(AddF, 0, [VF32(1.5), VF32(2.25)], [VF32(3.75)])
  expect_sem(SubF, 0, [VF32(1.5), VF32(2.25)], [VF32(-0.75)])
  expect_sem(MulF, 0, [VF32(1.5), VF32(2.0)], [VF32(3.0)])
  // +inf（IEEE 除零不 trap——#163；inf 位模式确定）
  expect_sem(DivF, 0, [VF32(1.0), VF32(0.0)], [
    VF32(Float::reinterpret_from_uint(0x7F800000U)),
  ])
  expect_sem(NegF, 0, [VF32(0.0)], [
    VF32(Float::reinterpret_from_uint(0x80000000U)),
  ]) // -0.0 位保真（NegF 一元负同语义）
  expect_sem(CastI2F, 0, [VI32(-7)], [VF32(-7.0)])
  expect_sem(CastF2I, 0, [VF32(2.7)], [VI32(2)])
  expect_sem(CastF2I, 0, [VF32(-2.7)], [VI32(-2)])
  expect_sem(CastF2I, 0, [VF32(Float::reinterpret_from_uint(0x7FC00000U))], [
    VI32(0),
  ])
  expect_sem(CastF2I, 0, [VF32(Float::reinterpret_from_uint(0x7149F2CAU))], [
    VI32(2147483647),
  ]) // f32 上界饱和
  expect_sem(EqF, 0, [VF32(1.5), VF32(2.5)], [VI32(0)])
  expect_sem(NeF, 0, [VF32(1.5), VF32(2.5)], [VI32(1)])
  expect_sem(LtF, 0, [VF32(1.5), VF32(2.5)], [VI32(1)])
  expect_sem(LeF, 0, [VF32(2.5), VF32(2.5)], [VI32(1)])
  expect_sem(GtF, 0, [VF32(1.5), VF32(2.5)], [VI32(0)])
  expect_sem(GeF, 0, [VF32(2.5), VF32(2.5)], [VI32(1)])
  expect_sem(CastU2F, 0, [VI32(-5)], [VF32(4294967291.0)]) // 病 31
  expect_sem(CastUQ2F, 0, [VI64(-1)], [VF32(18446744073709551616.0)]) // 2^64
  expect_sem(AddD, 0, [VF64(1.5), VF64(2.25)], [VF64(3.75)])
  expect_sem(SubD, 0, [VF64(1.5), VF64(2.25)], [VF64(-0.75)])
  expect_sem(MulD, 0, [VF64(1.5), VF64(2.0)], [VF64(3.0)])
  expect_sem(DivD, 0, [VF64(1.0), VF64(0.0)], [
    VF64(UInt64::reinterpret_as_double(0x7FF0000000000000UL)),
  ])
  expect_sem(NegD, 0, [VF64(0.0)], [
    VF64(UInt64::reinterpret_as_double(0x8000000000000000UL)),
  ])
  expect_sem(CastI2D, 0, [VI32(-7)], [VF64(-7.0)])
  expect_sem(CastF2D, 0, [VF32(1.5)], [VF64(1.5)])
  expect_sem(CastD2F, 0, [VF64(2.75)], [VF32(2.75)])
  expect_sem(CastD2I, 0, [VF64(2.7)], [VI32(2)])
  expect_sem(
    CastD2I,
    0,
    [VF64(UInt64::reinterpret_as_double(0x7FF8000000000000UL))],
    [VI32(0)],
  )
  expect_sem(EqD, 0, [VF64(1.5), VF64(2.5)], [VI32(0)])
  expect_sem(NeD, 0, [VF64(1.5), VF64(2.5)], [VI32(1)])
  expect_sem(LtD, 0, [VF64(1.5), VF64(2.5)], [VI32(1)])
  expect_sem(LeD, 0, [VF64(2.5), VF64(2.5)], [VI32(1)])
  expect_sem(GtD, 0, [VF64(1.5), VF64(2.5)], [VI32(0)])
  expect_sem(GeD, 0, [VF64(2.5), VF64(2.5)], [VI32(1)])
  expect_sem(CastU2D, 0, [VI32(-5)], [VF64(4294967291.0)])
  expect_sem(CastUQ2D, 0, [VI64(-1)], [VF64(18446744073709551615.0)])
}
