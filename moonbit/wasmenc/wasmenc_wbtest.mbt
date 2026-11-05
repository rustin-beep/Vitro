///|
/// wasmenc 白盒·**mini wasm 栈机**（soft-stack 双实现的 wasm 侧）：
/// 分型值栈（WVal）执行发射的 WInstr 序列——饱和转换**独立手写**
/// （sat_*，不依赖内建 to_int），与 Vitro 位模式域参照
/// （softstack_wbtest.mbt）形成双实现对拍（红线②：栈序/错值类错误
/// wasm 验证器不拦，字节往返不证明执行语义正确，必须模拟跑）。
/// 消费面：softstack_wbtest.mbt 的 expect_sem + anchors_wbtest.mbt。

///|
/// 载体分型值（Vitro u64 位模式栈 ↔ wasm 分型栈的桥接域）。
enum WVal {
  VI32(Int32)
  VI64(Int64)
  VF32(Float)
  VF64(Double)
}

///|
/// WVal → Vitro 位模式（i32 符号扩展 = push_i32 同形〔trap.mbt:44 亲读〕；
/// f32 低 32 位位模式零扩展 = exec_float PushConstF 同形；i64/f64 直通）。
fn wval_bits(v : WVal) -> UInt64 {
  match v {
    VI32(x) => x.to_int64().reinterpret_as_uint64()
    VI64(x) => x.reinterpret_as_uint64()
    VF32(f) => f.reinterpret_as_uint().to_uint64()
    VF64(d) => d.reinterpret_as_uint64()
  }
}

///|
/// soft-stack 机错误（下溢/类型错 = 模板栈序破坏；trap = 除法边界同构面）。
enum RunErr {
  Underflow
  TypeError
  Trap(String)
}

///|
/// pop 栈顶。
fn wv_pop(st : Array[WVal]) -> Result[WVal, RunErr] {
  if st.length() < 1 {
    return Err(Underflow)
  }
  Ok(st.remove(st.length() - 1))
}

///|
/// pop 两条（返回 (a, b)——a 在下 b 在顶，= wasm 弹序 = Vitro 先弹 b）。
fn wv_pop2(st : Array[WVal]) -> Result[(WVal, WVal), RunErr] {
  if st.length() < 2 {
    return Err(Underflow)
  }
  let b = st.remove(st.length() - 1)
  let a = st.remove(st.length() - 1)
  Ok((a, b))
}

///|
/// i32.trunc_sat_f32_s 的**独立手写饱和**（不依赖内建 to_int——与参照侧
/// 双实现；NaN→0 / ≥2^31→MAX / <-2^31→MIN；f32 可精确表示 ±2^31）。
fn sat_i32_of_f32(f : Float) -> Int32 {
  if f.is_nan() {
    return 0
  }
  if f >= 2147483648.0 {
    return 2147483647
  }
  if f < -2147483648.0 {
    return -2147483648
  }
  f.to_int()
}

///|
/// i32.trunc_sat_f64_s 独立饱和（f64 可精确表示 2^31-1 与 -2^31）。
fn sat_i32_of_f64(d : Double) -> Int32 {
  if d.is_nan() {
    return 0
  }
  if d >= 2147483647.0 {
    return 2147483647
  }
  if d < -2147483648.0 {
    return -2147483648
  }
  d.to_int()
}

///|
/// i64.trunc_sat_f64_s 独立饱和（±2^63 边界——f64 可精确表示）。
fn sat_i64_of_f64(d : Double) -> Int64 {
  if d.is_nan() {
    return 0L
  }
  if d >= 9223372036854775808.0 {
    return 9223372036854775807L
  }
  if d < -9223372036854775808.0 {
    return -9223372036854775808L
  }
  d.to_int64()
}

///|
/// mini wasm 栈机：执行指令序列（A 类指令面 + nop/drop/const；控制流/
/// 变量族不在对拍面——TypeError 红，即「模板栈序破坏」的检出形态）。
fn wasm_run(
  instrs : Array[WInstr],
  init : Array[WVal],
) -> Result[Array[WVal], RunErr] {
  let st : Array[WVal] = []
  for v in init {
    st.push(v)
  }
  for instr in instrs {
    match instr {
      WNop => ()
      WDrop =>
        match wv_pop(st) {
          Ok(_) => ()
          Err(e) => return Err(e)
        }
      WI32Const(v) => st.push(VI32(v))
      WI64Const(v) => st.push(VI64(v))
      WF32Const(v) => st.push(VF32(v))
      WF64Const(v) => st.push(VF64(v))
      WI32Extend8S =>
        match wv_pop(st) {
          Ok(VI32(x)) => {
            let b = x & 0xFF
            st.push(VI32(if b >= 128 { b - 256 } else { b }))
          }
          _ => return Err(TypeError)
        }
      WI32Eqz =>
        match wv_pop(st) {
          Ok(VI32(x)) => st.push(VI32(if x == 0 { 1 } else { 0 }))
          _ => return Err(TypeError)
        }
      WI32WrapI64 =>
        match wv_pop(st) {
          Ok(VI64(x)) => st.push(VI32(x.to_int()))
          _ => return Err(TypeError)
        }
      WI64ExtendI32S =>
        match wv_pop(st) {
          Ok(VI32(x)) => st.push(VI64(x.to_int64()))
          _ => return Err(TypeError)
        }
      WI64ExtendI32U =>
        match wv_pop(st) {
          Ok(VI32(x)) =>
            st.push(
              VI64(x.reinterpret_as_uint().to_uint64().reinterpret_as_int64()),
            )
          _ => return Err(TypeError)
        }
      WI32TruncSatF32S =>
        match wv_pop(st) {
          Ok(VF32(f)) => st.push(VI32(sat_i32_of_f32(f)))
          _ => return Err(TypeError)
        }
      WI32TruncSatF64S =>
        match wv_pop(st) {
          Ok(VF64(d)) => st.push(VI32(sat_i32_of_f64(d)))
          _ => return Err(TypeError)
        }
      WI64TruncSatF64S =>
        match wv_pop(st) {
          Ok(VF64(d)) => st.push(VI64(sat_i64_of_f64(d)))
          _ => return Err(TypeError)
        }
      WF32ConvertI32S =>
        match wv_pop(st) {
          Ok(VI32(x)) => st.push(VF32(Float::from_double(x.to_double())))
          _ => return Err(TypeError)
        }
      WF32ConvertI32U =>
        match wv_pop(st) {
          Ok(VI32(x)) =>
            st.push(
              VF32(Float::from_double(x.reinterpret_as_uint().to_double())),
            )
          _ => return Err(TypeError)
        }
      WF32ConvertI64U =>
        match wv_pop(st) {
          Ok(VI64(x)) =>
            st.push(
              VF32(Float::from_double(x.reinterpret_as_uint64().to_double())),
            )
          _ => return Err(TypeError)
        }
      WF64ConvertI32S =>
        match wv_pop(st) {
          Ok(VI32(x)) => st.push(VF64(x.to_double()))
          _ => return Err(TypeError)
        }
      WF64ConvertI32U =>
        match wv_pop(st) {
          Ok(VI32(x)) => st.push(VF64(x.reinterpret_as_uint().to_double()))
          _ => return Err(TypeError)
        }
      WF64ConvertI64S =>
        match wv_pop(st) {
          Ok(VI64(x)) => st.push(VF64(x.to_double()))
          _ => return Err(TypeError)
        }
      WF64ConvertI64U =>
        match wv_pop(st) {
          Ok(VI64(x)) => st.push(VF64(x.reinterpret_as_uint64().to_double()))
          _ => return Err(TypeError)
        }
      WF32DemoteF64 =>
        match wv_pop(st) {
          Ok(VF64(d)) => st.push(VF32(Float::from_double(d)))
          _ => return Err(TypeError)
        }
      WF64PromoteF32 =>
        match wv_pop(st) {
          Ok(VF32(f)) => st.push(VF64(f.to_double()))
          _ => return Err(TypeError)
        }
      WF32Neg =>
        match wv_pop(st) {
          Ok(VF32(f)) => st.push(VF32(-f))
          _ => return Err(TypeError)
        }
      WF64Neg =>
        match wv_pop(st) {
          Ok(VF64(d)) => st.push(VF64(-d))
          _ => return Err(TypeError)
        }
      _ => {
        // 二元族（比较/算术/位）
        let is_binary = match instr {
          WI32Eq
          | WI32Ne
          | WI32LtS
          | WI32LtU
          | WI32GtS
          | WI32GtU
          | WI32LeS
          | WI32LeU
          | WI32GeS
          | WI32GeU
          | WI32Add
          | WI32Sub
          | WI32Mul
          | WI32DivS
          | WI32DivU
          | WI32RemS
          | WI32RemU
          | WI32And
          | WI32Or
          | WI32Xor
          | WI64Eq
          | WI64Ne
          | WI64LtS
          | WI64LtU
          | WI64GtS
          | WI64GtU
          | WI64LeS
          | WI64LeU
          | WI64GeS
          | WI64GeU
          | WI64Add
          | WI64Sub
          | WI64Mul
          | WI64DivS
          | WI64DivU
          | WI64RemS
          | WI64RemU
          | WI64And
          | WI64Or
          | WI64Xor
          | WF32Eq
          | WF32Ne
          | WF32Lt
          | WF32Gt
          | WF32Le
          | WF32Ge
          | WF32Add
          | WF32Sub
          | WF32Mul
          | WF32Div
          | WF64Eq
          | WF64Ne
          | WF64Lt
          | WF64Gt
          | WF64Le
          | WF64Ge
          | WF64Add
          | WF64Sub
          | WF64Mul
          | WF64Div => true
          _ => false
        }
        if is_binary {
          let (a, b) = match wv_pop2(st) {
            Ok(p) => p
            Err(e) => return Err(e)
          }
          match wasm_binop(instr, a, b) {
            Ok(v) => st.push(v)
            Err(e) => return Err(e)
          }
        } else {
          return Err(TypeError) // 控制流/变量族不在 soft-stack 对拍面
        }
      }
    }
  }
  Ok(st)
}

///|
/// 二元指令求值（比较压 0/1 i32；除法 trap 面显式判——wasm 规范口径：
/// div_s/rem_s 除零+MIN/-1 双 trap；div_u/rem_u 仅除零）。
fn wasm_binop(instr : WInstr, a : WVal, b : WVal) -> Result[WVal, RunErr] {
  match instr {
    WI32Add =>
      match (a, b) {
        (VI32(x), VI32(y)) => Ok(VI32(x + y)) // MoonBit Int32 回绕（F1）
        _ => Err(TypeError)
      }
    WI32Sub =>
      match (a, b) {
        (VI32(x), VI32(y)) => Ok(VI32(x - y))
        _ => Err(TypeError)
      }
    WI32Mul =>
      match (a, b) {
        (VI32(x), VI32(y)) => Ok(VI32(x * y))
        _ => Err(TypeError)
      }
    WI32DivS =>
      match (a, b) {
        (VI32(x), VI32(y)) => {
          if y == 0 {
            return Err(Trap("i32.div_s: 除零"))
          }
          if x == -2147483648 && y == -1 {
            return Err(Trap("i32.div_s: INT_MIN/-1"))
          }
          Ok(VI32(x / y))
        }
        _ => Err(TypeError)
      }
    WI32DivU =>
      match (a, b) {
        (VI32(x), VI32(y)) => {
          if y == 0 {
            return Err(Trap("i32.div_u: 除零"))
          }
          Ok(
            VI32(
              (x.reinterpret_as_uint() / y.reinterpret_as_uint()).reinterpret_as_int(),
            ),
          )
        }
        _ => Err(TypeError)
      }
    WI32RemS =>
      match (a, b) {
        (VI32(x), VI32(y)) => {
          if y == 0 {
            return Err(Trap("i32.rem_s: 除零"))
          }
          if x == -2147483648 && y == -1 {
            return Err(Trap("i32.rem_s: INT_MIN/-1"))
          }
          Ok(VI32(x % y))
        }
        _ => Err(TypeError)
      }
    WI32RemU =>
      match (a, b) {
        (VI32(x), VI32(y)) => {
          if y == 0 {
            return Err(Trap("i32.rem_u: 除零"))
          }
          Ok(
            VI32(
              (x.reinterpret_as_uint() % y.reinterpret_as_uint()).reinterpret_as_int(),
            ),
          )
        }
        _ => Err(TypeError)
      }
    WI32And =>
      match (a, b) {
        (VI32(x), VI32(y)) => Ok(VI32(x & y))
        _ => Err(TypeError)
      }
    WI32Or =>
      match (a, b) {
        (VI32(x), VI32(y)) => Ok(VI32(x | y))
        _ => Err(TypeError)
      }
    WI32Xor =>
      match (a, b) {
        (VI32(x), VI32(y)) => Ok(VI32(x ^ y))
        _ => Err(TypeError)
      }
    WI32Eq =>
      match (a, b) {
        (VI32(x), VI32(y)) => Ok(VI32(if x == y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WI32Ne =>
      match (a, b) {
        (VI32(x), VI32(y)) => Ok(VI32(if x != y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WI32LtS =>
      match (a, b) {
        (VI32(x), VI32(y)) => Ok(VI32(if x < y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WI32LtU =>
      match (a, b) {
        (VI32(x), VI32(y)) =>
          Ok(
            VI32(
              if x.reinterpret_as_uint() < y.reinterpret_as_uint() {
                1
              } else {
                0
              },
            ),
          )
        _ => Err(TypeError)
      }
    WI32GtS =>
      match (a, b) {
        (VI32(x), VI32(y)) => Ok(VI32(if x > y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WI32GtU =>
      match (a, b) {
        (VI32(x), VI32(y)) =>
          Ok(
            VI32(
              if x.reinterpret_as_uint() > y.reinterpret_as_uint() {
                1
              } else {
                0
              },
            ),
          )
        _ => Err(TypeError)
      }
    WI32LeS =>
      match (a, b) {
        (VI32(x), VI32(y)) => Ok(VI32(if x <= y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WI32LeU =>
      match (a, b) {
        (VI32(x), VI32(y)) =>
          Ok(
            VI32(
              if x.reinterpret_as_uint() <= y.reinterpret_as_uint() {
                1
              } else {
                0
              },
            ),
          )
        _ => Err(TypeError)
      }
    WI32GeS =>
      match (a, b) {
        (VI32(x), VI32(y)) => Ok(VI32(if x >= y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WI32GeU =>
      match (a, b) {
        (VI32(x), VI32(y)) =>
          Ok(
            VI32(
              if x.reinterpret_as_uint() >= y.reinterpret_as_uint() {
                1
              } else {
                0
              },
            ),
          )
        _ => Err(TypeError)
      }
    WI64Add =>
      match (a, b) {
        (VI64(x), VI64(y)) => Ok(VI64(x + y))
        _ => Err(TypeError)
      }
    WI64Sub =>
      match (a, b) {
        (VI64(x), VI64(y)) => Ok(VI64(x - y))
        _ => Err(TypeError)
      }
    WI64Mul =>
      match (a, b) {
        (VI64(x), VI64(y)) => Ok(VI64(x * y))
        _ => Err(TypeError)
      }
    WI64DivS =>
      match (a, b) {
        (VI64(x), VI64(y)) => {
          if y == 0L {
            return Err(Trap("i64.div_s: 除零"))
          }
          if x == -9223372036854775808L && y == -1L {
            return Err(Trap("i64.div_s: LLONG_MIN/-1"))
          }
          Ok(VI64(x / y))
        }
        _ => Err(TypeError)
      }
    WI64DivU =>
      match (a, b) {
        (VI64(x), VI64(y)) => {
          if y == 0L {
            return Err(Trap("i64.div_u: 除零"))
          }
          Ok(
            VI64(
              (x.reinterpret_as_uint64() / y.reinterpret_as_uint64()).reinterpret_as_int64(),
            ),
          )
        }
        _ => Err(TypeError)
      }
    WI64RemS =>
      match (a, b) {
        (VI64(x), VI64(y)) => {
          if y == 0L {
            return Err(Trap("i64.rem_s: 除零"))
          }
          if x == -9223372036854775808L && y == -1L {
            return Err(Trap("i64.rem_s: LLONG_MIN/-1"))
          }
          Ok(VI64(x % y))
        }
        _ => Err(TypeError)
      }
    WI64RemU =>
      match (a, b) {
        (VI64(x), VI64(y)) => {
          if y == 0L {
            return Err(Trap("i64.rem_u: 除零"))
          }
          Ok(
            VI64(
              (x.reinterpret_as_uint64() % y.reinterpret_as_uint64()).reinterpret_as_int64(),
            ),
          )
        }
        _ => Err(TypeError)
      }
    WI64And =>
      match (a, b) {
        (VI64(x), VI64(y)) => Ok(VI64(x & y))
        _ => Err(TypeError)
      }
    WI64Or =>
      match (a, b) {
        (VI64(x), VI64(y)) => Ok(VI64(x | y))
        _ => Err(TypeError)
      }
    WI64Xor =>
      match (a, b) {
        (VI64(x), VI64(y)) => Ok(VI64(x ^ y))
        _ => Err(TypeError)
      }
    WI64Eq =>
      match (a, b) {
        (VI64(x), VI64(y)) => Ok(VI32(if x == y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WI64Ne =>
      match (a, b) {
        (VI64(x), VI64(y)) => Ok(VI32(if x != y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WI64LtS =>
      match (a, b) {
        (VI64(x), VI64(y)) => Ok(VI32(if x < y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WI64LtU =>
      match (a, b) {
        (VI64(x), VI64(y)) =>
          Ok(
            VI32(
              if x.reinterpret_as_uint64() < y.reinterpret_as_uint64() {
                1
              } else {
                0
              },
            ),
          )
        _ => Err(TypeError)
      }
    WI64GtS =>
      match (a, b) {
        (VI64(x), VI64(y)) => Ok(VI32(if x > y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WI64GtU =>
      match (a, b) {
        (VI64(x), VI64(y)) =>
          Ok(
            VI32(
              if x.reinterpret_as_uint64() > y.reinterpret_as_uint64() {
                1
              } else {
                0
              },
            ),
          )
        _ => Err(TypeError)
      }
    WI64LeS =>
      match (a, b) {
        (VI64(x), VI64(y)) => Ok(VI32(if x <= y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WI64LeU =>
      match (a, b) {
        (VI64(x), VI64(y)) =>
          Ok(
            VI32(
              if x.reinterpret_as_uint64() <= y.reinterpret_as_uint64() {
                1
              } else {
                0
              },
            ),
          )
        _ => Err(TypeError)
      }
    WI64GeS =>
      match (a, b) {
        (VI64(x), VI64(y)) => Ok(VI32(if x >= y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WI64GeU =>
      match (a, b) {
        (VI64(x), VI64(y)) =>
          Ok(
            VI32(
              if x.reinterpret_as_uint64() >= y.reinterpret_as_uint64() {
                1
              } else {
                0
              },
            ),
          )
        _ => Err(TypeError)
      }
    WF32Add =>
      match (a, b) {
        (VF32(x), VF32(y)) => Ok(VF32(x + y))
        _ => Err(TypeError)
      }
    WF32Sub =>
      match (a, b) {
        (VF32(x), VF32(y)) => Ok(VF32(x - y))
        _ => Err(TypeError)
      }
    WF32Mul =>
      match (a, b) {
        (VF32(x), VF32(y)) => Ok(VF32(x * y))
        _ => Err(TypeError)
      }
    WF32Div =>
      match (a, b) {
        (VF32(x), VF32(y)) => Ok(VF32(x / y)) // IEEE：除零=±inf/NaN 不 trap
        _ => Err(TypeError)
      }
    WF32Eq =>
      match (a, b) {
        (VF32(x), VF32(y)) => Ok(VI32(if x == y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WF32Ne =>
      match (a, b) {
        (VF32(x), VF32(y)) => Ok(VI32(if x != y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WF32Lt =>
      match (a, b) {
        (VF32(x), VF32(y)) => Ok(VI32(if x < y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WF32Gt =>
      match (a, b) {
        (VF32(x), VF32(y)) => Ok(VI32(if x > y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WF32Le =>
      match (a, b) {
        (VF32(x), VF32(y)) => Ok(VI32(if x <= y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WF32Ge =>
      match (a, b) {
        (VF32(x), VF32(y)) => Ok(VI32(if x >= y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WF64Add =>
      match (a, b) {
        (VF64(x), VF64(y)) => Ok(VF64(x + y))
        _ => Err(TypeError)
      }
    WF64Sub =>
      match (a, b) {
        (VF64(x), VF64(y)) => Ok(VF64(x - y))
        _ => Err(TypeError)
      }
    WF64Mul =>
      match (a, b) {
        (VF64(x), VF64(y)) => Ok(VF64(x * y))
        _ => Err(TypeError)
      }
    WF64Div =>
      match (a, b) {
        (VF64(x), VF64(y)) => Ok(VF64(x / y))
        _ => Err(TypeError)
      }
    WF64Eq =>
      match (a, b) {
        (VF64(x), VF64(y)) => Ok(VI32(if x == y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WF64Ne =>
      match (a, b) {
        (VF64(x), VF64(y)) => Ok(VI32(if x != y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WF64Lt =>
      match (a, b) {
        (VF64(x), VF64(y)) => Ok(VI32(if x < y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WF64Gt =>
      match (a, b) {
        (VF64(x), VF64(y)) => Ok(VI32(if x > y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WF64Le =>
      match (a, b) {
        (VF64(x), VF64(y)) => Ok(VI32(if x <= y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    WF64Ge =>
      match (a, b) {
        (VF64(x), VF64(y)) => Ok(VI32(if x >= y { 1 } else { 0 }))
        _ => Err(TypeError)
      }
    _ => Err(TypeError)
  }
}
