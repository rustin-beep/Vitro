///| L7 执行层·VM 域·executor：**F（f32）/ D（f64）/ Q（i64）三族**
/// （Rust `executor/float.rs` 逐句照搬）。
///
/// **转换契约（探针实证，2026-09-26）**：MoonBit `Double::to_int` =
/// `%f64_to_i32_saturate`（**饱和**语义，与 Rust `as i32` 一致——NaN→0 /
/// inf→±MAX / 2.7→2）；`Int64::to_int` = 低 32 位截断；f32 位模式经
/// `UInt::reinterpret_as_float` / `Float::reinterpret_as_uint`；f64 位模式经
/// `reinterpret_as_double` / `reinterpret_as_uint64`（host 包同款）。
///
/// **除零 trap 照搬**（Rust：DivF/DivD 显式检查 `b == 0.0` → 教学 trap，
/// 不是 IEEE inf——浮点除零在教学子集里是错误而非无穷大）；比较族 IEEE
/// 精确语义（E1：无 epsilon 容差——容差使 0.1+0.2==0.3 判真，与 Clang
/// golden 矛盾）。
///
/// **Q 族回绕语义与 i32 族不同（对拍契约）**：AddQ/SubQ/MulQ 是
/// `wrapping`（**不 trap**——Rust 同款；i32 族的 Add/Sub/Mul 才是 i64 中转
/// + 教学 trap）；DivQ/ModQ 的 LLONG_MIN/-1 与除零检查照搬。

///|
fn VitroVM::execute_float(
  self : VitroVM,
  op : @opcode.OpCode,
  operand : Int,
  line : Int,
  column : Int,
) -> Unit {
  match op {
    PushConstF =>
      // f32 位模式经 i32 operand（低 32 位零扩展压栈——位模式无符号语义）
      self.push(operand.reinterpret_as_uint().to_uint64())
    AddF | SubF | MulF => {
      let b = self.pop().to_uint().reinterpret_as_float()
      let a = self.pop().to_uint().reinterpret_as_float()
      let r = match op {
        AddF => a + b
        SubF => a - b
        MulF => a * b
        _ => a
      }
      self.push(Float::reinterpret_as_uint(r).to_uint64())
    }
    DivF => {
      let b = self.pop().to_uint().reinterpret_as_float()
      let a = self.pop().to_uint().reinterpret_as_float()
      if b == Float::from_double(0.0) {
        self.trap("浮点数除以零", line, column)
      } else {
        let r = a / b
        self.push(Float::reinterpret_as_uint(r).to_uint64())
      }
    }
    NegF => {
      let a = self.pop().to_uint().reinterpret_as_float()
      let r = Float::from_double(0.0) - a
      self.push(Float::reinterpret_as_uint(r).to_uint64())
    }
    EqF | NeF | LtF | LeF | GtF | GeF => {
      let b = self.pop().to_uint().reinterpret_as_float()
      let a = self.pop().to_uint().reinterpret_as_float()
      let r : Bool = match op {
        EqF => a == b
        NeF => a != b
        LtF => a < b
        LeF => a <= b
        GtF => a > b
        GeF => a >= b
        _ => false
      }
      self.push(if r { 1UL } else { 0UL })
    }
    CastI2F => {
      let a = self.pop_i32()
      let r = Float::from_double(a.to_double())
      self.push(Float::reinterpret_as_uint(r).to_uint64())
    }
    CastF2I => {
      let a = self.pop().to_uint().reinterpret_as_float()
      // 饱和语义（Rust as i32 = NaN→0 / inf→±MAX）
      self.push_i32(Float::to_int(a))
    }
    _ => ()
  }
}

///|
fn VitroVM::execute_double(
  self : VitroVM,
  op : @opcode.OpCode,
  operand : Int,
  line : Int,
  column : Int,
) -> Unit {
  match op {
    PushConstD =>
      match self.f64_constants.get(operand) {
        Some(v) => self.push(v.reinterpret_as_uint64())
        None =>
          self.trap(
            "f64常量索引越界: " + operand.to_string(),
            line,
            column,
          )
      }
    AddD | SubD | MulD => {
      let b = self.pop().reinterpret_as_double()
      let a = self.pop().reinterpret_as_double()
      let r = match op {
        AddD => a + b
        SubD => a - b
        MulD => a * b
        _ => a
      }
      self.push(r.reinterpret_as_uint64())
    }
    DivD => {
      let b = self.pop().reinterpret_as_double()
      let a = self.pop().reinterpret_as_double()
      if b == 0.0 {
        self.trap("double 除以零", line, column)
      } else {
        let r = a / b
        self.push(r.reinterpret_as_uint64())
      }
    }
    NegD => {
      let a = self.pop().reinterpret_as_double()
      let r = -a
      self.push(r.reinterpret_as_uint64())
    }
    CastI2D => {
      let a = self.pop_i32()
      self.push(a.to_double().reinterpret_as_uint64())
    }
    CastF2D => {
      let a = self.pop().to_uint().reinterpret_as_float()
      self.push(a.to_double().reinterpret_as_uint64())
    }
    CastD2I => {
      let a = self.pop().reinterpret_as_double()
      // 饱和语义（%f64_to_i32_saturate = Rust as i32）
      self.push_i32(a.to_int())
    }
    CastD2F => {
      let a = self.pop().reinterpret_as_double()
      self.push(Float::reinterpret_as_uint(Double::to_float(a)).to_uint64())
    }
    EqD | NeD | LtD | LeD | GtD | GeD => {
      let b = self.pop().reinterpret_as_double()
      let a = self.pop().reinterpret_as_double()
      let r : Bool = match op {
        EqD => a == b
        NeD => a != b
        LtD => a < b
        LeD => a <= b
        GtD => a > b
        GeD => a >= b
        _ => false
      }
      self.push(if r { 1UL } else { 0UL })
    }
    _ => ()
  }
}

///|
fn VitroVM::execute_longlong(
  self : VitroVM,
  op : @opcode.OpCode,
  operand : Int,
  line : Int,
  column : Int,
) -> Unit {
  match op {
    PushConstQ =>
      match self.i64_constants.get(operand) {
        Some(v) => self.push(v.reinterpret_as_uint64())
        None =>
          self.trap(
            "i64常量索引越界: " + operand.to_string(),
            line,
            column,
          )
      }
    AddQ | SubQ | MulQ => {
      // Q 族回绕（Rust wrapping——不 trap，与 i32 族的教学 trap 分口径）
      let b = self.pop_i64()
      let a = self.pop_i64()
      let r = match op {
        AddQ => a + b
        SubQ => a - b
        MulQ => a * b
        _ => a
      }
      self.push(r.reinterpret_as_uint64())
    }
    DivQ => {
      let b = self.pop_i64()
      let a = self.pop_i64()
      if b == 0L {
        self.trap("long long 除以零", line, column)
      } else if a == -9223372036854775808L && b == -1L {
        self.trap(
          "long long 除法溢出。LLONG_MIN / -1 的结果超出了 long long 能表示的范围。",
          line, column,
        )
      } else {
        self.push((a / b).reinterpret_as_uint64())
      }
    }
    ModQ => {
      let b = self.pop_i64()
      let a = self.pop_i64()
      if b == 0L {
        self.trap("long long 取模除以零", line, column)
      } else if a == -9223372036854775808L && b == -1L {
        self.trap(
          "long long 取模溢出。LLONG_MIN % -1 的结果未定义，超出了 long long 能表示的范围。",
          line, column,
        )
      } else {
        self.push((a % b).reinterpret_as_uint64())
      }
    }
    NegQ => {
      let a = self.pop_i64()
      if a == -9223372036854775808L {
        self.trap(
          "long long 取反溢出。-LLONG_MIN 的结果超出了 long long 能表示的范围。",
          line, column,
        )
      } else {
        self.push((-a).reinterpret_as_uint64())
      }
    }
    CastI2Q => {
      let a = self.pop_i32()
      self.push(a.to_int64().reinterpret_as_uint64())
    }
    CastQ2I => {
      let a = self.pop_i64()
      // 低 32 位截断（Rust as i32；Int64::to_int 实证为截断语义）
      self.push_i32(a.to_int())
    }
    CastQ2D => {
      let a = self.pop_i64()
      self.push(a.to_double().reinterpret_as_uint64())
    }
    CastD2Q => {
      let a = self.pop().reinterpret_as_double()
      // f64→i64 饱和（Rust as i64 同款语义；MoonBit to_int64 为饱和实现）
      self.push(a.to_int64().reinterpret_as_uint64())
    }
    EqQ | NeQ | LtQ | LeQ | GtQ | GeQ => {
      let b = self.pop_i64()
      let a = self.pop_i64()
      let r : Bool = match op {
        EqQ => a == b
        NeQ => a != b
        LtQ => a < b
        LeQ => a <= b
        GtQ => a > b
        GeQ => a >= b
        _ => false
      }
      self.push(if r { 1UL } else { 0UL })
    }
    _ => ()
  }
}
