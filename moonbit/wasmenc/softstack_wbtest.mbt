///|
/// soft-stack 双实现对拍（红线②的机检形态）：mini wasm 栈机（分型域，
/// wasmenc_wbtest.mbt）执行发射序列 vs Vitro 语义直算参照（位模式域，
/// exec_* 臂镜像，本文件）vs 手写期望——三方逐位一致 + 栈效应断言。
/// 探针会话 4 次执行错误全为栈序/错值类（**wasm 验证器不拦**），字节
/// 往返不证明执行语义正确，必须模拟跑。
/// 样本域诚实登记：除法/取模 trap 边界断言**双 trap**（两侧同 trap 面
/// = A 类直映 trap 同构锚）；NaN 参与运算的 payload 非确定面（R2）样本
/// 回避——NaN 仅作位模式传递与饱和转换输入。
///
/// 批 1b 扩面：**B 类 50 条全量**（vitro_ref_b + expect_sem_state——
/// 状态域三方对拍：栈 + globals〔$fb/$sp/$steps〕+ 内存关键字节 +
/// host 调用序；检查类模板的 trap 面（NULL/溢出/域越界）全部双 trap
/// 断言——**栈序类错误验证器不拦，执行语义断言是唯一防线**）。

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

// ══════════════ B 类参照（批 1b：状态域 exec_* 镜像——50 条） ══════════════

///|
/// 参照状态（位模式域 + 内存/全局镜像——与 wasm 侧**独立内存**双实现）。
struct RefState {
  stack : Array[UInt64]
  mem : Array[Byte]
  fb : Int32
  mut sp : Int32
  mut steps : Int32
}

///|
/// 参照访存检查（check_access 镜像：NULL 区 <0x1000 + 区间上界；失败即
/// trap 终局——render_mem_fault 亲读 trap.mbt:408）。
fn ref_check(st : RefState, addr : UInt32, n : UInt32) -> Result[Unit, String] {
  if addr < 0x1000U {
    return Err("NULL 区解引用（E3083 面）")
  }
  let end = addr.to_int64() + n.to_int64()
  if end > st.mem.length().to_int64() {
    return Err("区间越界（E3086/E3087 面）")
  }
  Ok(())
}

///|
/// 参照读 u32（小端）。
fn ref_load_u32(st : RefState, addr : UInt32) -> UInt32 {
  let a = addr.reinterpret_as_int()
  let mut v = 0U
  for i = 0; i < 4; i = i + 1 {
    v = v | (st.mem[a + i].to_uint() << (i * 8))
  }
  v
}

///|
fn ref_store_u32(st : RefState, addr : UInt32, v : UInt32) -> Unit {
  let a = addr.reinterpret_as_int()
  for i = 0; i < 4; i = i + 1 {
    st.mem[a + i] = ((v >> (i * 8)) & 0xFFU).reinterpret_as_int().to_byte()
  }
}

///|
fn ref_load_u64(st : RefState, addr : UInt32) -> UInt64 {
  let a = addr.reinterpret_as_int()
  let mut v = 0UL
  for i = 0; i < 8; i = i + 1 {
    v = v | (st.mem[a + i].to_uint64() << (i * 8))
  }
  v
}

///|
fn ref_store_u64(st : RefState, addr : UInt32, v : UInt64) -> Unit {
  let a = addr.reinterpret_as_int()
  for i = 0; i < 8; i = i + 1 {
    st.mem[a + i] = ((v >> (i * 8)) & 0xFFUL)
      .to_uint()
      .reinterpret_as_int()
      .to_byte()
  }
}

///|
/// B 类参照主入口（exec_local/exec_global/exec_memory/exec_arith/
/// exec_float/exec_debug 臂镜像——位模式域直算）。
fn vitro_ref_b(
  op : @opcode.OpCode,
  operand : Int32,
  ctx : EmitCtx,
  st : RefState,
) -> Result[Unit, String] {
  fn pop(st : RefState) -> Result[UInt64, String] {
    if st.stack.length() < 1 {
      return Err("下溢")
    }
    Ok(st.stack.remove(st.stack.length() - 1))
  }
  fn pop_i32(st : RefState) -> Result[Int32, String] {
    match pop(st) {
      Ok(v) => Ok(v.to_int())
      Err(e) => Err(e)
    }
  }
  fn pop_i64(st : RefState) -> Result[Int64, String] {
    match pop(st) {
      Ok(v) => Ok(v.reinterpret_as_int64())
      Err(e) => Err(e)
    }
  }
  fn push_i32(st : RefState, v : Int32) -> Unit {
    st.stack.push(v.to_int64().reinterpret_as_uint64())
  }
  match op {
    // ── 局部族（execute_local 镜像：fb+off 编址 + 域检查）──
    LoadLocal | LoadLocalD | LoadLocalQ => {
      let addr = st.fb.reinterpret_as_uint() + operand.reinterpret_as_uint()
      let width = if op is LoadLocal { 4U } else { 8U }
      match ref_check(st, addr, width) {
        Err(e) => Err(e)
        Ok(_) =>
          if op is LoadLocal {
            push_i32(st, ref_load_u32(st, addr).reinterpret_as_int())
            Ok(())
          } else {
            st.stack.push(ref_load_u64(st, addr))
            Ok(())
          }
      }
    }
    StoreLocal | StoreLocalD | StoreLocalQ => {
      let val = match pop(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let addr = st.fb.reinterpret_as_uint() + operand.reinterpret_as_uint()
      let width = if op is StoreLocal { 4U } else { 8U }
      match ref_check(st, addr, width) {
        Err(e) => Err(e)
        Ok(_) =>
          if op is StoreLocal {
            ref_store_u32(st, addr, val.to_uint())
            Ok(())
          } else {
            ref_store_u64(st, addr, val)
            Ok(())
          }
      }
    }
    GetFrameBase => {
      st.stack.push(st.fb.reinterpret_as_uint().to_uint64())
      Ok(())
    }
    // ── 全局族（execute_global 镜像：0x1000+off 编址）──
    LoadGlobal | LoadGlobalD | LoadGlobalQ | LoadGlobalByte | LoadGlobalUByte => {
      let addr = 0x1000U + operand.reinterpret_as_uint()
      let width = match op {
        LoadGlobal => 4U
        LoadGlobalD | LoadGlobalQ => 8U
        _ => 1U
      }
      match ref_check(st, addr, width) {
        Err(e) => Err(e)
        Ok(_) =>
          match op {
            LoadGlobal => {
              push_i32(st, ref_load_u32(st, addr).reinterpret_as_int())
              Ok(())
            }
            LoadGlobalD | LoadGlobalQ => {
              st.stack.push(ref_load_u64(st, addr))
              Ok(())
            }
            _ => {
              // i8 符号/零扩展（#177 镜像）
              let b = st.mem[addr.reinterpret_as_int()].to_int() << 24 >> 24
              push_i32(st, if op is LoadGlobalByte { b } else { b & 0xFF })
              Ok(())
            }
          }
      }
    }
    StoreGlobal | StoreGlobalD | StoreGlobalQ | StoreGlobalByte => {
      let val = match pop(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let addr = 0x1000U + operand.reinterpret_as_uint()
      let width = match op {
        StoreGlobal => 4U
        StoreGlobalD | StoreGlobalQ => 8U
        _ => 1U
      }
      match ref_check(st, addr, width) {
        Err(e) => Err(e)
        Ok(_) =>
          match op {
            StoreGlobal => {
              ref_store_u32(st, addr, val.to_uint())
              Ok(())
            }
            StoreGlobalD | StoreGlobalQ => {
              ref_store_u64(st, addr, val)
              Ok(())
            }
            _ => {
              st.mem[addr.reinterpret_as_int()] = (val.to_int() & 0xFF).to_byte()
              Ok(())
            }
          }
      }
    }
    // ── 栈操作 ──
    Dup => {
      if st.stack.length() < 1 {
        return Err("Dup: 栈空")
      }
      st.stack.push(st.stack[st.stack.length() - 1])
      Ok(())
    }
    Swap => {
      if st.stack.length() < 2 {
        return Err("Swap: 栈不足")
      }
      let n = st.stack.length()
      let tmp = st.stack[n - 1]
      st.stack[n - 1] = st.stack[n - 2]
      st.stack[n - 2] = tmp
      Ok(())
    }
    // ── 访存族（execute_memory 镜像）──
    LoadMem | LoadMemByte | LoadMemUByte | LoadMemD | LoadMemQ => {
      let addr = match pop(st) {
        Ok(v) => v.to_uint()
        Err(e) => return Err(e)
      }
      let width = if op is LoadMem {
        4U
      } else if op is LoadMemD || op is LoadMemQ {
        8U
      } else {
        1U
      }
      match ref_check(st, addr, width) {
        Err(e) => Err(e)
        Ok(_) =>
          match op {
            LoadMem => {
              push_i32(st, ref_load_u32(st, addr).reinterpret_as_int())
              Ok(())
            }
            LoadMemD | LoadMemQ => {
              st.stack.push(ref_load_u64(st, addr))
              Ok(())
            }
            _ => {
              let b = st.mem[addr.reinterpret_as_int()].to_int() << 24 >> 24
              push_i32(st, if op is LoadMemByte { b } else { b & 0xFF })
              Ok(())
            }
          }
      }
    }
    StoreMem | StoreMemByte | StoreMemD | StoreMemQ => {
      // 先弹值再弹地址（exec_memory 对拍契约）
      let val = match pop(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let addr = match pop(st) {
        Ok(v) => v.to_uint()
        Err(e) => return Err(e)
      }
      let width = if op is StoreMem {
        4U
      } else if op is StoreMemD || op is StoreMemQ {
        8U
      } else {
        1U
      }
      match ref_check(st, addr, width) {
        Err(e) => Err(e)
        Ok(_) =>
          match op {
            StoreMem => {
              ref_store_u32(st, addr, val.to_uint())
              Ok(())
            }
            StoreMemD | StoreMemQ => {
              ref_store_u64(st, addr, val)
              Ok(())
            }
            _ => {
              st.mem[addr.reinterpret_as_int()] = (val.to_int() & 0xFF).to_byte()
              Ok(())
            }
          }
      }
    }
    SplitD | SplitQ => {
      let val = match pop(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      // 两半各 i32 语义符号扩展（exec_memory.mbt:76-84 镜像——low 先 high 后）
      push_i32(st, val.to_uint().reinterpret_as_int())
      push_i32(st, (val >> 32).to_uint().reinterpret_as_int())
      Ok(())
    }
    StackAlloc => {
      let size = match pop_i32(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      if size < 0 {
        return Err("StackAlloc: 分配的栈空间大小为负数")
      }
      let aligned = ((size + 3) & -4).reinterpret_as_uint()
      if aligned > st.sp.reinterpret_as_uint() {
        return Err("StackAlloc: 栈溢出")
      }
      if st.sp.reinterpret_as_uint() - aligned < 0x1000U {
        return Err("StackAlloc: 栈溢出（触及保留区）")
      }
      st.sp = (st.sp.reinterpret_as_uint() - aligned).reinterpret_as_int()
      st.stack.push(st.sp.reinterpret_as_uint().to_uint64())
      Ok(())
    }
    Memcpy => {
      // 弹序 dest（顶）/src/n（exec_memory 对拍契约）；检查失败即终局
      let dest = match pop(st) {
        Ok(v) => v.to_uint()
        Err(e) => return Err(e)
      }
      let src = match pop(st) {
        Ok(v) => v.to_uint()
        Err(e) => return Err(e)
      }
      let n = match pop_i32(st) {
        Ok(v) => v.reinterpret_as_uint()
        Err(e) => return Err(e)
      }
      match ref_check(st, dest, n) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      match ref_check(st, src, n) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      // memmove（临时缓冲——现役 memory.copy 同语义）
      let nn = n.reinterpret_as_int()
      if nn > 0 {
        let tmp : Array[Byte] = []
        for i = 0; i < nn; i = i + 1 {
          tmp.push(st.mem[src.reinterpret_as_int() + i])
        }
        for i = 0; i < nn; i = i + 1 {
          st.mem[dest.reinterpret_as_int() + i] = tmp[i]
        }
      }
      st.stack.push(dest.to_uint64())
      Ok(())
    }
    Memset => {
      let ptr = match pop(st) {
        Ok(v) => v.to_uint()
        Err(e) => return Err(e)
      }
      let value = match pop(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let size = match pop_i32(st) {
        Ok(v) => v.reinterpret_as_uint()
        Err(e) => return Err(e)
      }
      match ref_check(st, ptr, size) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      let byte_val = (value & 0xFFUL).to_uint().to_byte()
      let nn = size.reinterpret_as_int()
      for i = 0; i < nn; i = i + 1 {
        st.mem[ptr.reinterpret_as_int() + i] = byte_val
      }
      st.stack.push(ptr.to_uint64())
      Ok(())
    }
    // ── 溢出检查算术（exec_arith/exec_float 镜像——i64 中转 + 教学 trap）──
    Add | Sub | Mul => {
      let b = match pop_i32(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let a = match pop_i32(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let r : Int64 = match op {
        Add => a.to_int64() + b.to_int64()
        Sub => a.to_int64() - b.to_int64()
        _ => a.to_int64() * b.to_int64()
      }
      if r > 2147483647L || r < -2147483648L {
        return Err(
          match op {
            Add => "整数加法溢出"
            Sub => "整数减法溢出"
            _ => "整数乘法溢出"
          },
        )
      }
      push_i32(st, r.to_int())
      Ok(())
    }
    Neg => {
      let a = match pop_i32(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      if a == -2147483648 {
        return Err("整数取反溢出。-INT_MIN")
      }
      push_i32(st, -a)
      Ok(())
    }
    NegQ => {
      let a = match pop_i64(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      if a == -9223372036854775808L {
        return Err("long long 取反溢出。-LLONG_MIN")
      }
      st.stack.push((-a).reinterpret_as_uint64())
      Ok(())
    }
    UNeg => {
      let a = match pop(st) {
        Ok(v) => v.to_uint()
        Err(e) => return Err(e)
      }
      st.stack.push(
        (0U - a).reinterpret_as_int().to_int64().reinterpret_as_uint64(),
      )
      Ok(())
    }
    UNegQ => {
      let a = match pop(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      st.stack.push(0UL - a)
      Ok(())
    }
    // ── 移位域检查（exec_arith 镜像：0~31/0~63 越界 trap）──
    Shl | Shr | LShr => {
      let b = match pop_i32(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let a = match pop_i32(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      if b < 0 || b > 31 {
        return Err("移位量越界（0~31）")
      }
      let r = match op {
        Shl => a << b
        Shr => a >> b
        _ => (a.reinterpret_as_uint() >> b).reinterpret_as_int()
      }
      push_i32(st, r)
      Ok(())
    }
    ShlQ | ShrQ | LShrQ => {
      let b = match pop_i64(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let a = match pop_i64(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      if b < 0L || b > 63L {
        return Err("移位量越界（0~63）")
      }
      let bb = b.to_int()
      let r : Int64 = match op {
        ShlQ => a << bb
        ShrQ => a >> bb
        _ => (a.reinterpret_as_uint64() >> bb).reinterpret_as_int64()
      }
      st.stack.push(r.reinterpret_as_uint64())
      Ok(())
    }
    // ── 常量池 ──
    PushConstD =>
      match ctx.f64_constants.get(operand) {
        Some(v) => {
          st.stack.push(v.reinterpret_as_uint64())
          Ok(())
        }
        None => Err("f64常量索引越界")
      }
    PushConstQ =>
      match ctx.i64_constants.get(operand) {
        Some(v) => {
          st.stack.push(v.reinterpret_as_uint64())
          Ok(())
        }
        None => Err("i64常量索引越界")
      }
    TruncUByte => {
      let a = match pop_i32(st) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      push_i32(st, a & 0xFF)
      Ok(())
    }
    // ── 教学观测 ──
    StepEvent => {
      st.steps = st.steps + 1
      Ok(())
    }
    TrapBounds => {
      if st.stack.length() < 1 {
        return Err("TrapBounds: 值栈为空")
      }
      let index = st.stack[st.stack.length() - 1].reinterpret_as_int64()
      let size = if operand >= 0 {
        match ctx.symbol_sizes.get(operand) {
          Some(s) => s
          None => 0
        }
      } else {
        -operand
      }
      if index < 0L || index >= size.to_int64() {
        return Err("数组越界 (E3086)")
      }
      Ok(())
    }
    _ => Err("B 类参照未覆盖 op=\{op.name()}")
  }
}

// ══════════════ 状态域三方断言器（批 1b） ══════════════

///|
/// B 类三方对拍断言器：发射 → mini wasm 机（分型域+状态）vs Vitro 参照
/// （位模式域+独立内存）vs 手写期望——终栈逐位 + 终全局 + 内存关键字节
/// + host 调用序 + 栈效应净差；trap 面双断言（同 trap 才绿）。
fn expect_sem_state(
  op : @opcode.OpCode,
  operand : Int32,
  ctx : EmitCtx,
  init : Array[WVal],
  globals_init : Array[(Int32, WVal)],
  mem_preset : Array[(Int32, Int32)],
  want : Array[WVal],
  globals_want : Array[(Int32, WVal)],
  mem_want : Array[(Int32, Int32)],
  host_want : Array[(Int32, Int32)],
) -> Unit raise {
  let instrs = match emit_group(op, operand, ctx) {
    Ok(i) => i
    Err(_) => fail("emit \{op.name()} 失败（B 类模板应可发射）")
  }
  // wasm 侧
  let wasm_mem : Array[Byte] = Array::make(64 * 1024, (0x00).to_byte())
  for pair in mem_preset {
    wasm_mem[pair.0] = pair.1.to_byte()
  }
  let m = mach_init(globals_init, wasm_mem, 0x1234L)
  let wasm_res : Result[Unit, RunErr] = wasm_exec(instrs, init, m)
  // 参照侧（独立内存双实现）
  let ref_mem : Array[Byte] = Array::make(64 * 1024, (0x00).to_byte())
  for pair in mem_preset {
    ref_mem[pair.0] = pair.1.to_byte()
  }
  let st : RefState = {
    stack: [],
    mem: ref_mem,
    fb: match globals_get_int(globals_init, G_FB) {
      Some(v) => v
      None => 0
    },
    sp: match globals_get_int(globals_init, G_SPT) {
      Some(v) => v
      None => 0
    },
    steps: match globals_get_int(globals_init, G_STEPS) {
      Some(v) => v
      None => 0
    },
  }
  for v in init {
    st.stack.push(wval_bits(v))
  }
  let ref_res = vitro_ref_b(op, operand, ctx, st)
  // 双 trap / 双成功 同型断言
  match (wasm_res, ref_res) {
    (Err(Trap(wmsg)), Err(_)) => {
      // 双 trap ✓——trap 定位信息消费（1a 遗留 payload 清账）
      if wmsg.length() == 0 {
        fail("\{op.name()}: wasm trap 文案为空")
      }
      return
    }
    (Err(e), Ok(_)) =>
      fail(
        "\{op.name()}: wasm 机 \{err_desc(e)} 但参照成功——trap 面不同构或栈序破坏",
      )
    (Ok(_), Err(rmsg)) =>
      fail(
        "\{op.name()}: 参照 trap（\{rmsg}）但 wasm 机成功——trap 面不同构",
      )
    (Err(e), Err(_)) =>
      fail(
        "\{op.name()}: wasm 机 \{err_desc(e)}（非 Trap 形态）vs 参照 trap——栈序/类型破坏",
      )
    (Ok(_), Ok(_)) => ()
  }
  // 终栈逐位
  let want_bits : Array[UInt64] = []
  for w in want {
    want_bits.push(wval_bits(w))
  }
  if m.stack.length() != want_bits.length() {
    fail(
      "\{op.name()}: wasm 终栈深 \{m.stack.length()} != 期望 \{want_bits.length()}（栈效应/栈序红）",
    )
  }
  for i = 0; i < want_bits.length(); i = i + 1 {
    if wval_bits(m.stack[i]) != want_bits[i] {
      fail(
        "\{op.name()}[\{i}]: wasm = \{wval_bits(m.stack[i])} != 期望 \{want_bits[i]}（mini 栈机语义红）",
      )
    }
    if st.stack[i] != want_bits[i] {
      fail(
        "\{op.name()}[\{i}]: 参照 = \{st.stack[i]} != 期望 \{want_bits[i]}（Vitro 直算红）",
      )
    }
  }
  // 栈效应净差（表声明 vs 实测——红线②静态面）
  let s = template_spec(op)
  if s.pops >= 0 {
    let delta = m.stack.length() - init.length()
    if delta != s.pushes - s.pops {
      fail(
        "\{op.name()}: wasm 栈净差 \{delta} != 表声明 \{s.pushes - s.pops}",
      )
    }
  }
  // 终全局
  for pair in globals_want {
    let got = m.globals[pair.0]
    if got != pair.1 {
      fail(
        "\{op.name()}: global[\{pair.0}] 位模式 \{wval_bits(got)} != 期望 \{wval_bits(pair.1)}（状态面红）",
      )
    }
  }
  // steps 特判（StepEvent——参照侧计数 vs wasm 侧 G_STEPS）
  if op is StepEvent && m.globals[G_STEPS] != VI32(st.steps) {
    fail("StepEvent: wasm steps != 参照 steps（组前计步漂移）")
  }
  // 内存关键字节（两侧独立内存终态一致 + 等于期望）
  for pair in mem_want {
    if m.mem[pair.0] != pair.1.to_byte() {
      fail(
        "\{op.name()}: wasm mem[\{pair.0}]=\{m.mem[pair.0]} != 期望 \{pair.1}",
      )
    }
    if st.mem[pair.0] != pair.1.to_byte() {
      fail(
        "\{op.name()}: 参照 mem[\{pair.0}]=\{st.mem[pair.0]} != 期望 \{pair.1}（双实现内存终态分叉）",
      )
    }
  }
  // host 调用序
  if m.host_calls.length() != host_want.length() {
    fail(
      "\{op.name()}: host 调用数 \{m.host_calls.length()} != 期望 \{host_want.length()}",
    )
  }
  for i = 0; i < host_want.length(); i = i + 1 {
    if m.host_calls[i] != host_want[i] {
      fail(
        "\{op.name()}: host[\{i}]=\{m.host_calls[i]} != 期望 \{host_want[i]}",
      )
    }
  }
}

///|
/// globals_init 的 i32 取值辅助。
fn globals_get_int(globals : Array[(Int32, WVal)], idx : Int32) -> Int32? {
  for pair in globals {
    if pair.0 == idx {
      match pair.1 {
        VI32(v) => return Some(v)
        _ => return None
      }
    }
  }
  None
}

///|
/// RunErr 描述（断言失败文案）。
fn err_desc(e : RunErr) -> String {
  match e {
    Underflow => "下溢"
    TypeError => "类型错"
    Trap(msg) => "trap(\{msg})"
  }
}

// ══════════════ B 类样本（50 条全覆盖——每族关键语义 + 边界 + trap 对） ══════════════

///|
/// 局部族六条 + GetFrameBase（fb=0x2000 样态）。
test "softstack_local_family" {
  let ctx = EmitCtx::empty()
  let fb : Array[(Int32, WVal)] = [(G_FB, VI32(0x2000))]
  // LoadLocal：读 4 字节符号扩展
  expect_sem_state(
    LoadLocal,
    8,
    ctx,
    [],
    fb,
    [(0x2008, 0x34), (0x2009, 0x12), (0x200A, 0x00), (0x200B, 0x00)],
    [VI32(0x1234)],
    [],
    [],
    [],
  )
  // 负值符号扩展（0xFFFFFFF8 → -8）
  expect_sem_state(
    LoadLocal,
    4,
    ctx,
    [],
    fb,
    [(0x2004, 0xF8), (0x2005, 0xFF), (0x2006, 0xFF), (0x2007, 0xFF)],
    [VI32(-8)],
    [],
    [],
    [],
  )
  // StoreLocal：写 4 字节
  expect_sem_state(
    StoreLocal,
    12,
    ctx,
    [VI32(0xABCD)],
    fb,
    [],
    [],
    [],
    [(0x200C, 0xCD), (0x200D, 0xAB), (0x200E, 0x00), (0x200F, 0x00)],
    [],
  )
  // LoadLocalD/Q：8 字节
  expect_sem_state(
    LoadLocalD,
    16,
    ctx,
    [],
    fb,
    [
      (0x2010, 0x00),
      (0x2011, 0x00),
      (0x2012, 0x00),
      (0x2013, 0x00),
      (0x2014, 0x00),
      (0x2015, 0x00),
      (0x2016, 0xF8),
      (0x2017, 0x3F),
    ],
    [VF64(1.5)],
    [],
    [],
    [],
  )
  expect_sem_state(
    LoadLocalQ,
    16,
    ctx,
    [],
    fb,
    [
      (0x2010, 0xFF),
      (0x2011, 0xFF),
      (0x2012, 0xFF),
      (0x2013, 0xFF),
      (0x2014, 0xFF),
      (0x2015, 0xFF),
      (0x2016, 0xFF),
      (0x2017, 0xFF),
    ],
    [VI64(-1)],
    [],
    [],
    [],
  )
  expect_sem_state(
    StoreLocalD,
    24,
    ctx,
    [VF64(1.5)],
    fb,
    [],
    [],
    [],
    [
      (0x2018, 0x00),
      (0x2019, 0x00),
      (0x201A, 0x00),
      (0x201B, 0x00),
      (0x201C, 0x00),
      (0x201D, 0x00),
      (0x201E, 0xF8),
      (0x201F, 0x3F),
    ],
    [],
  )
  expect_sem_state(
    StoreLocalQ,
    24,
    ctx,
    [VI64(-2)],
    fb,
    [],
    [],
    [],
    [
      (0x2018, 0xFE),
      (0x2019, 0xFF),
      (0x201A, 0xFF),
      (0x201B, 0xFF),
      (0x201C, 0xFF),
      (0x201D, 0xFF),
      (0x201E, 0xFF),
      (0x201F, 0xFF),
    ],
    [],
  )
  // GetFrameBase
  expect_sem_state(GetFrameBase, 0, ctx, [], fb, [], [VI32(0x2000)], [], [], [])
}

///|
/// 全局族九条（0x1000 基址；char 字节粒度 #177）。
test "softstack_global_family" {
  let ctx = EmitCtx::empty()
  // LoadGlobal：operand=8 → addr 0x1008
  expect_sem_state(
    LoadGlobal,
    8,
    ctx,
    [],
    [],
    [(0x1008, 0x34), (0x1009, 0x12), (0x100A, 0x00), (0x100B, 0x00)],
    [VI32(0x1234)],
    [],
    [],
    [],
  )
  expect_sem_state(
    StoreGlobal,
    8,
    ctx,
    [VI32(-1)],
    [],
    [],
    [],
    [],
    [(0x1008, 0xFF), (0x1009, 0xFF), (0x100A, 0xFF), (0x100B, 0xFF)],
    [],
  )
  expect_sem_state(
    LoadGlobalD,
    0,
    ctx,
    [],
    [],
    [
      (0x1000, 0x00),
      (0x1001, 0x00),
      (0x1002, 0x00),
      (0x1003, 0x00),
      (0x1004, 0x00),
      (0x1005, 0x00),
      (0x1006, 0xF8),
      (0x1007, 0x3F),
    ],
    [VF64(1.5)],
    [],
    [],
    [],
  )
  expect_sem_state(
    StoreGlobalD,
    0,
    ctx,
    [VF64(-0.5)],
    [],
    [],
    [],
    [],
    [
      (0x1000, 0x00),
      (0x1001, 0x00),
      (0x1002, 0x00),
      (0x1003, 0x00),
      (0x1004, 0x00),
      (0x1005, 0x00),
      (0x1006, 0xE0),
      (0x1007, 0xBF),
    ],
    [],
  )
  expect_sem_state(
    LoadGlobalQ,
    16,
    ctx,
    [],
    [],
    [
      (0x1010, 0xFF),
      (0x1011, 0xFF),
      (0x1012, 0xFF),
      (0x1013, 0xFF),
      (0x1014, 0xFF),
      (0x1015, 0xFF),
      (0x1016, 0xFF),
      (0x1017, 0xFF),
    ],
    [VI64(-1)],
    [],
    [],
    [],
  )
  expect_sem_state(
    StoreGlobalQ,
    16,
    ctx,
    [VI64(255)],
    [],
    [],
    [],
    [],
    [
      (0x1010, 0xFF),
      (0x1011, 0x00),
      (0x1012, 0x00),
      (0x1013, 0x00),
      (0x1014, 0x00),
      (0x1015, 0x00),
      (0x1016, 0x00),
      (0x1017, 0x00),
    ],
    [],
  )
  // char 1 字节粒度（病 33：c=200 读回 -56；病 32：unsigned 0xAB 不染符号）
  expect_sem_state(
    StoreGlobalByte,
    0,
    ctx,
    [VI32(200)],
    [],
    [],
    [],
    [],
    [(0x1000, 0xC8)],
    [],
  )
  expect_sem_state(
    LoadGlobalByte,
    0,
    ctx,
    [],
    [],
    [(0x1000, 0xC8)],
    [VI32(-56)],
    [],
    [],
    [],
  )
  expect_sem_state(
    LoadGlobalUByte,
    0,
    ctx,
    [],
    [],
    [(0x1000, 0xAB)],
    [VI32(0xAB)],
    [],
    [],
    [],
  )
  // StoreGlobalByte 只落低 8 位不抹邻居（#177：写 0x34 不动 0x1001）
  expect_sem_state(
    StoreGlobalByte,
    0,
    ctx,
    [VI32(0x1234)],
    [],
    [(0x1001, 0x99)],
    [],
    [],
    [(0x1000, 0x34), (0x1001, 0x99)],
    [],
  )
}

///|
/// Dup/Swap（暂存槽重排——栈效应 1→2 / 2→2）。
test "softstack_dupswap_family" {
  let ctx = EmitCtx::empty()
  expect_sem_state(Dup, 0, ctx, [VI32(7)], [], [], [VI32(7), VI32(7)], [], [], [])
  expect_sem_state(
    Swap,
    0,
    ctx,
    [VI32(3), VI32(9)],
    [],
    [],
    [VI32(9), VI32(3)],
    [],
    [],
    [],
  )
  expect_sem_state(
    Swap,
    0,
    ctx,
    [VI64(-1), VI32(42)],
    [],
    [],
    [VI32(42), VI64(-1)],
    [],
    [],
    [],
  )
}

///|
/// 访存族九条（NULL trap 对 + 读写 + byte 粒度）。
test "softstack_mem_family" {
  let ctx = EmitCtx::empty()
  expect_sem_state(
    LoadMem,
    0,
    ctx,
    [VI32(0x3000)],
    [],
    [(0x3000, 0x78), (0x3001, 0x56), (0x3002, 0x00), (0x3003, 0x00)],
    [VI32(0x5678)],
    [],
    [],
    [],
  )
  expect_sem_state(LoadMem, 0, ctx, [VI32(0x800)], [], [], [], [], [], []) // 双 trap：NULL 区
  expect_sem_state(
    StoreMem,
    0,
    ctx,
    [VI32(0x3000), VI32(0xCAFE)],
    [],
    [],
    [],
    [],
    [(0x3000, 0xFE), (0x3001, 0xCA), (0x3002, 0x00), (0x3003, 0x00)],
    [],
  )
  expect_sem_state(
    StoreMem,
    0,
    ctx,
    [VI32(0xFFF), VI32(1)],
    [],
    [],
    [],
    [],
    [],
    [],
  ) // 双 trap：NULL
  expect_sem_state(
    LoadMemByte,
    0,
    ctx,
    [VI32(0x3000)],
    [],
    [(0x3000, 0xC8)],
    [VI32(-56)],
    [],
    [],
    [],
  )
  expect_sem_state(
    LoadMemUByte,
    0,
    ctx,
    [VI32(0x3000)],
    [],
    [(0x3000, 0xC8)],
    [VI32(200)],
    [],
    [],
    [],
  )
  expect_sem_state(
    StoreMemByte,
    0,
    ctx,
    [VI32(0x3000), VI32(0x1234)],
    [],
    [(0x3001, 0x99)],
    [],
    [],
    [(0x3000, 0x34), (0x3001, 0x99)],
    [],
  )
  expect_sem_state(
    LoadMemD,
    0,
    ctx,
    [VI32(0x3000)],
    [],
    [
      (0x3000, 0x00),
      (0x3001, 0x00),
      (0x3002, 0x00),
      (0x3003, 0x00),
      (0x3004, 0x00),
      (0x3005, 0x00),
      (0x3006, 0xF8),
      (0x3007, 0x3F),
    ],
    [VF64(1.5)],
    [],
    [],
    [],
  )
  expect_sem_state(
    StoreMemD,
    0,
    ctx,
    [VI32(0x3000), VF64(-0.5)],
    [],
    [],
    [],
    [],
    [
      (0x3000, 0x00),
      (0x3001, 0x00),
      (0x3002, 0x00),
      (0x3003, 0x00),
      (0x3004, 0x00),
      (0x3005, 0x00),
      (0x3006, 0xE0),
      (0x3007, 0xBF),
    ],
    [],
  )
  expect_sem_state(
    LoadMemQ,
    0,
    ctx,
    [VI32(0x3000)],
    [],
    [
      (0x3000, 0xFF),
      (0x3001, 0xFF),
      (0x3002, 0xFF),
      (0x3003, 0xFF),
      (0x3004, 0xFF),
      (0x3005, 0xFF),
      (0x3006, 0xFF),
      (0x3007, 0xFF),
    ],
    [VI64(-1)],
    [],
    [],
    [],
  )
  expect_sem_state(
    StoreMemQ,
    0,
    ctx,
    [VI32(0x3000), VI64(0x1122334455667788L)],
    [],
    [],
    [],
    [],
    [
      (0x3000, 0x88),
      (0x3001, 0x77),
      (0x3002, 0x66),
      (0x3003, 0x55),
      (0x3004, 0x44),
      (0x3005, 0x33),
      (0x3006, 0x22),
      (0x3007, 0x11),
    ],
    [],
  )
}

///|
/// SplitD/SplitQ + StackAlloc（三重检查 trap 对）。
test "softstack_split_alloc_family" {
  let ctx = EmitCtx::empty()
  // SplitD：1.5 位模式 0x3FF8000000000000 → low=0 / high=0x3FF80000
  expect_sem_state(
    SplitD,
    0,
    ctx,
    [VF64(1.5)],
    [],
    [],
    [VI32(0), VI32(0x3FF80000)],
    [],
    [],
    [],
  )
  // SplitQ：-1 → 两半全 -1（审阅 P1-1 锚）
  expect_sem_state(
    SplitQ,
    0,
    ctx,
    [VI64(-1)],
    [],
    [],
    [VI32(-1), VI32(-1)],
    [],
    [],
    [],
  )
  expect_sem_state(
    SplitQ,
    0,
    ctx,
    [VI64(0x0000000200000001L)],
    [],
    [],
    [VI32(1), VI32(2)],
    [],
    [],
    [],
  )
  // 高半负（符号扩展）
  expect_sem_state(
    SplitQ,
    0,
    ctx,
    [VI64(0x8000000000000000L)],
    [],
    [],
    [VI32(0), VI32(-2147483648)],
    [],
    [],
    [],
  )
  // StackAlloc：正常（sp=0x8000，分配 12 → 对齐 12 → 新顶 0x7FF4）
  expect_sem_state(
    StackAlloc,
    0,
    ctx,
    [VI32(12)],
    [(G_SPT, VI32(0x8000))],
    [],
    [VI32(0x7FF4)],
    [(G_SPT, VI32(0x7FF4))],
    [],
    [],
  )
  // 对齐：5 → 8
  expect_sem_state(
    StackAlloc,
    0,
    ctx,
    [VI32(5)],
    [(G_SPT, VI32(0x8000))],
    [],
    [VI32(0x7FF8)],
    [(G_SPT, VI32(0x7FF8))],
    [],
    [],
  )
  // 双 trap：负数
  expect_sem_state(
    StackAlloc,
    0,
    ctx,
    [VI32(-1)],
    [(G_SPT, VI32(0x8000))],
    [],
    [],
    [],
    [],
    [],
  )
  // 双 trap：溢出（aligned > sp）
  expect_sem_state(
    StackAlloc,
    0,
    ctx,
    [VI32(0x9000)],
    [(G_SPT, VI32(0x8000))],
    [],
    [],
    [],
    [],
    [],
  )
  // 双 trap：保留区（sp−aligned < 0x1000）
  expect_sem_state(
    StackAlloc,
    0,
    ctx,
    [VI32(0x7800)],
    [(G_SPT, VI32(0x8000))],
    [],
    [],
    [],
    [],
    [],
  )
}

///|
/// Memcpy/Memset（memmove 重叠 + 低 8 位 + NULL trap 对 + dest 压回）。
test "softstack_memcpy_family" {
  let ctx = EmitCtx::empty()
  // Memcpy 正常（栈序 [n, src, dest]——dest 顶）
  expect_sem_state(
    Memcpy,
    0,
    ctx,
    [VI32(4), VI32(0x3000), VI32(0x3100)],
    [],
    [(0x3000, 0x11), (0x3001, 0x22), (0x3002, 0x33), (0x3003, 0x44)],
    [VI32(0x3100)],
    [],
    [(0x3100, 0x11), (0x3101, 0x22), (0x3102, 0x33), (0x3103, 0x44)],
    [],
  )
  // memmove 重叠（src 0x3000 n=4 → dst 0x3002）
  expect_sem_state(
    Memcpy,
    0,
    ctx,
    [VI32(4), VI32(0x3000), VI32(0x3002)],
    [],
    [
      (0x3000, 0x11),
      (0x3001, 0x22),
      (0x3002, 0x33),
      (0x3003, 0x44),
      (0x3004, 0x55),
      (0x3005, 0x66),
    ],
    [VI32(0x3002)],
    [],
    [(0x3002, 0x11), (0x3003, 0x22), (0x3004, 0x33), (0x3005, 0x44)],
    [],
  )
  // 双 trap：dest NULL
  expect_sem_state(
    Memcpy,
    0,
    ctx,
    [VI32(4), VI32(0x3000), VI32(0x800)],
    [],
    [],
    [],
    [],
    [],
    [],
  )
  // 双 trap：src NULL
  expect_sem_state(
    Memcpy,
    0,
    ctx,
    [VI32(4), VI32(0x800), VI32(0x3000)],
    [],
    [],
    [],
    [],
    [],
    [],
  )
  // Memset：value=0xABCD → 低 8 位 0xCD（栈序 [size, value, ptr]）
  expect_sem_state(
    Memset,
    0,
    ctx,
    [VI32(4), VI64(0xABCD), VI32(0x3100)],
    [],
    [],
    [VI32(0x3100)],
    [],
    [(0x3100, 0xCD), (0x3101, 0xCD), (0x3102, 0xCD), (0x3103, 0xCD)],
    [],
  )
  // 双 trap：NULL
  expect_sem_state(
    Memset,
    0,
    ctx,
    [VI32(4), VI64(0xAB), VI32(0x800)],
    [],
    [],
    [],
    [],
    [],
    [],
  )
}

///|
/// 溢出检查算术族（Add/Sub/Mul/Neg/NegQ/UNeg/UNegQ——教学 trap 对全带）。
test "softstack_overflow_family" {
  let ctx = EmitCtx::empty()
  expect_sem_state(
    Add,
    0,
    ctx,
    [VI32(7), VI32(3)],
    [],
    [],
    [VI32(10)],
    [],
    [],
    [],
  )
  expect_sem_state(
    Add,
    0,
    ctx,
    [VI32(2147483647), VI32(1)],
    [],
    [],
    [],
    [],
    [],
    [],
  ) // 双 trap：上溢
  expect_sem_state(
    Add,
    0,
    ctx,
    [VI32(-2147483648), VI32(-1)],
    [],
    [],
    [],
    [],
    [],
    [],
  ) // 双 trap：下溢
  expect_sem_state(
    Sub,
    0,
    ctx,
    [VI32(7), VI32(10)],
    [],
    [],
    [VI32(-3)],
    [],
    [],
    [],
  )
  expect_sem_state(
    Sub,
    0,
    ctx,
    [VI32(-2147483648), VI32(1)],
    [],
    [],
    [],
    [],
    [],
    [],
  ) // 双 trap
  expect_sem_state(
    Mul,
    0,
    ctx,
    [VI32(65536), VI32(65536)],
    [],
    [],
    [VI32(0)],
    [],
    [],
    [],
  ) // 2^32 恰在域内 → 0
  expect_sem_state(
    Mul,
    0,
    ctx,
    [VI32(65536), VI32(65537)],
    [],
    [],
    [],
    [],
    [],
    [],
  ) // 双 trap
  expect_sem_state(
    Mul,
    0,
    ctx,
    [VI32(-2147483648), VI32(-1)],
    [],
    [],
    [],
    [],
    [],
    [],
  ) // 双 trap
  expect_sem_state(Neg, 0, ctx, [VI32(5)], [], [], [VI32(-5)], [], [], [])
  expect_sem_state(Neg, 0, ctx, [VI32(0)], [], [], [VI32(0)], [], [], [])
  expect_sem_state(Neg, 0, ctx, [VI32(-2147483648)], [], [], [], [], [], []) // 双 trap：-INT_MIN
  expect_sem_state(NegQ, 0, ctx, [VI64(5)], [], [], [VI64(-5)], [], [], [])
  expect_sem_state(
    NegQ,
    0,
    ctx,
    [VI64(-9223372036854775808L)],
    [],
    [],
    [],
    [],
    [],
    [],
  ) // 双 trap
  expect_sem_state(UNeg, 0, ctx, [VI32(5)], [], [], [VI32(-5)], [], [], []) // u32 域回绕不 trap
  expect_sem_state(UNeg, 0, ctx, [VI32(0)], [], [], [VI32(0)], [], [], [])
  expect_sem_state(UNeg, 0, ctx, [VI32(-1)], [], [], [VI32(1)], [], [], []) // 0xFFFFFFFF → 1
  expect_sem_state(UNegQ, 0, ctx, [VI64(5)], [], [], [VI64(-5)], [], [], [])
  expect_sem_state(UNegQ, 0, ctx, [VI64(-1)], [], [], [VI64(1)], [], [], [])
}

///|
/// 移位域检查族（Shl/Shr/LShr + Q 族——域 trap 对全带；负移位量 u32 落非法侧）。
test "softstack_shift_family" {
  let ctx = EmitCtx::empty()
  expect_sem_state(
    Shl,
    0,
    ctx,
    [VI32(3), VI32(4)],
    [],
    [],
    [VI32(48)],
    [],
    [],
    [],
  )
  expect_sem_state(
    Shl,
    0,
    ctx,
    [VI32(1), VI32(31)],
    [],
    [],
    [VI32(-2147483648)],
    [],
    [],
    [],
  )
  expect_sem_state(Shl, 0, ctx, [VI32(1), VI32(32)], [], [], [], [], [], []) // 双 trap：域 0~31
  expect_sem_state(Shl, 0, ctx, [VI32(1), VI32(-1)], [], [], [], [], [], []) // 双 trap：负 → u32 大值
  expect_sem_state(
    Shr,
    0,
    ctx,
    [VI32(-8), VI32(1)],
    [],
    [],
    [VI32(-4)],
    [],
    [],
    [],
  ) // 算术右移
  expect_sem_state(
    Shr,
    0,
    ctx,
    [VI32(-1), VI32(31)],
    [],
    [],
    [VI32(-1)],
    [],
    [],
    [],
  )
  expect_sem_state(Shr, 0, ctx, [VI32(1), VI32(64)], [], [], [], [], [], []) // 双 trap
  expect_sem_state(
    LShr,
    0,
    ctx,
    [VI32(-8), VI32(1)],
    [],
    [],
    [VI32(0x7FFFFFFC)],
    [],
    [],
    [],
  )
  expect_sem_state(
    LShr,
    0,
    ctx,
    [VI32(-1), VI32(28)],
    [],
    [],
    [VI32(15)],
    [],
    [],
    [],
  )
  expect_sem_state(LShr, 0, ctx, [VI32(1), VI32(32)], [], [], [], [], [], []) // 双 trap
  expect_sem_state(
    ShlQ,
    0,
    ctx,
    [VI64(3), VI64(4)],
    [],
    [],
    [VI64(48)],
    [],
    [],
    [],
  )
  expect_sem_state(
    ShlQ,
    0,
    ctx,
    [VI64(1), VI64(63)],
    [],
    [],
    [VI64(-9223372036854775808L)],
    [],
    [],
    [],
  )
  expect_sem_state(ShlQ, 0, ctx, [VI64(1), VI64(64)], [], [], [], [], [], []) // 双 trap：域 0~63
  expect_sem_state(
    ShrQ,
    0,
    ctx,
    [VI64(-8), VI64(1)],
    [],
    [],
    [VI64(-4)],
    [],
    [],
    [],
  )
  expect_sem_state(ShrQ, 0, ctx, [VI64(1), VI64(100)], [], [], [], [], [], []) // 双 trap
  expect_sem_state(
    LShrQ,
    0,
    ctx,
    [VI64(-8), VI64(1)],
    [],
    [],
    [VI64(9223372036854775804L)],
    [],
    [],
    [],
  )
  expect_sem_state(
    LShrQ,
    0,
    ctx,
    [VI64(-1), VI64(60)],
    [],
    [],
    [VI64(15)],
    [],
    [],
    [],
  )
  expect_sem_state(LShrQ, 0, ctx, [VI64(1), VI64(-1)], [], [], [], [], [], []) // 双 trap：负
}

///|
/// 常量池 + TruncUByte + StepEvent + TrapBounds。
test "softstack_constpool_misc_family" {
  let ctx : EmitCtx = {
    f64_constants: [1.5, -0.25],
    i64_constants: [42L, -1L],
    argc: 0,
    argv_addr: 0,
    fallthrough_pc: 0,
    host_argv_ptr: 0,
    symbol_sizes: [4, 0],
  }
  expect_sem_state(PushConstD, 0, ctx, [], [], [], [VF64(1.5)], [], [], [])
  expect_sem_state(PushConstD, 1, ctx, [], [], [], [VF64(-0.25)], [], [], [])
  expect_sem_state(PushConstQ, 0, ctx, [], [], [], [VI64(42)], [], [], [])
  expect_sem_state(PushConstQ, 1, ctx, [], [], [], [VI64(-1)], [], [], [])
  // 池索引越界 = 发射侧 fail loud（BadOperand）
  match emit_group(PushConstD, 9, ctx) {
    Err(BadOperand(_)) => ()
    Ok(_) => fail("PushConstD 池外索引不应发射")
    Err(_) => fail("拒载形态分叉")
  }
  // TruncUByte：低 8 位零扩展（病 33：300 → 44）
  expect_sem_state(
    TruncUByte,
    0,
    ctx,
    [VI32(300)],
    [],
    [],
    [VI32(44)],
    [],
    [],
    [],
  )
  expect_sem_state(
    TruncUByte,
    0,
    ctx,
    [VI32(200)],
    [],
    [],
    [VI32(200)],
    [],
    [],
    [],
  )
  expect_sem_state(
    TruncUByte,
    0,
    ctx,
    [VI32(-56)],
    [],
    [],
    [VI32(200)],
    [],
    [],
    [],
  )
  // StepEvent：栈不变 + steps+1（组前计步）
  expect_sem_state(
    StepEvent,
    42,
    ctx,
    [VI32(7)],
    [(G_STEPS, VI32(9))],
    [],
    [VI32(7)],
    [(G_STEPS, VI32(10))],
    [],
    [],
  )
  // TrapBounds：域内通过（栈不变）；越界双 trap；operand<0 字面量形状
  expect_sem_state(TrapBounds, 0, ctx, [VI32(3)], [], [], [VI32(3)], [], [], []) // size=4 域内
  expect_sem_state(TrapBounds, 0, ctx, [VI32(4)], [], [], [], [], [], []) // 双 trap：idx==size
  expect_sem_state(TrapBounds, 0, ctx, [VI32(-1)], [], [], [], [], [], []) // 双 trap：负
  expect_sem_state(TrapBounds, -3, ctx, [VI32(2)], [], [], [VI32(2)], [], [], []) // 字面量 size=3 域内
  expect_sem_state(TrapBounds, -3, ctx, [VI32(3)], [], [], [], [], [], []) // 双 trap
}
