///| L7 执行层·VM 域·executor：**算术 / 比较 / 位运算族**（Rust
/// `executor/arithmetic.rs` 逐句照搬）。
///
/// 溢出语义（§0 纠正过的口径，对拍契约）：`Add/Sub/Mul/Neg` 有符号族走
/// i64 中间值 + 范围检查 → **教学 trap**；`U*` 无符号族回绕（MoonBit `Int`
/// 四则静默回绕 = Rust `wrapping_*` 同语义，F1）；`Div/Mod` 的
/// `INT_MIN / -1` 先拦截（Rust `%` panic 击穿 FFI 的事故防御——坑 8）。

///|
fn VitroVM::execute_arithmetic(
  self : VitroVM,
  op : @opcode.OpCode,
  _operand : Int,
  line : Int,
  column : Int,
) -> Unit {
  match op {
    Add => {
      let b = self.pop_i32()
      let a = self.pop_i32()
      let r = a.to_int64() + b.to_int64()
      if r > 2147483647L || r < -2147483648L {
        self.trap(
          "整数加法溢出。两个很大的正数（或很小的负数）相加超出了 int 能表示的范围。",
          line, column,
        )
      } else {
        self.push(r.reinterpret_as_uint64())
      }
    }
    UAdd => {
      let b = self.pop_i32()
      let a = self.pop_i32()
      self.push_i32(a + b)
    }
    Sub => {
      let b = self.pop_i32()
      let a = self.pop_i32()
      let r = a.to_int64() - b.to_int64()
      if r > 2147483647L || r < -2147483648L {
        self.trap(
          "整数减法溢出。被减数太小而减数太大，结果超出了 int 能表示的范围。",
          line, column,
        )
      } else {
        self.push(r.reinterpret_as_uint64())
      }
    }
    USub => {
      let b = self.pop_i32()
      let a = self.pop_i32()
      self.push_i32(a - b)
    }
    Mul => {
      let b = self.pop_i32()
      let a = self.pop_i32()
      let r = a.to_int64() * b.to_int64()
      if r > 2147483647L || r < -2147483648L {
        self.trap(
          "整数乘法溢出。乘积太大，超出了 int 能表示的范围。",
          line, column,
        )
      } else {
        self.push(r.reinterpret_as_uint64())
      }
    }
    UMul => {
      let b = self.pop_i32()
      let a = self.pop_i32()
      self.push_i32(a * b)
    }
    Div => {
      let b = self.pop_i32()
      let a = self.pop_i32()
      if b == 0 {
        let msg = self.format_div_zero_error(a)
        self.trap(msg, line, column)
      } else if a == -2147483648 && b == -1 {
        self.trap(
          "整数除法溢出。INT_MIN / -1 的结果超出了 int 能表示的范围。",
          line, column,
        )
      } else {
        self.push_i32(a / b)
      }
    }
    UDiv => {
      let b = self.pop_addr()
      let a = self.pop_addr()
      if b == 0U {
        let msg = self.format_div_zero_error(a.reinterpret_as_int())
        self.trap(msg, line, column)
      } else {
        self.push((a / b).to_uint64())
      }
    }
    Mod => {
      let b = self.pop_i32()
      let a = self.pop_i32()
      if b == 0 {
        let msg = self.format_div_zero_error(a)
        self.trap(msg, line, column)
      } else if a == -2147483648 && b == -1 {
        // INT_MIN % -1 未定义——先拦截（坑 8：Rust % 在此处 panic）
        self.trap(
          "整数取模溢出。INT_MIN % -1 的结果未定义，超出了 int 能表示的范围。",
          line, column,
        )
      } else {
        self.push_i32(a % b)
      }
    }
    UMod => {
      let b = self.pop_addr()
      let a = self.pop_addr()
      if b == 0U {
        let msg = self.format_div_zero_error(a.reinterpret_as_int())
        self.trap(msg, line, column)
      } else {
        self.push((a % b).to_uint64())
      }
    }
    Neg => {
      let a = self.pop_i32()
      if a == -2147483648 {
        self.trap(
          "整数取反溢出。-INT_MIN 的结果超出了 int 能表示的范围。",
          line, column,
        )
      } else {
        self.push_i32(-a)
      }
    }
    UNeg => {
      let a = self.pop_addr()
      self.push((0U - a).to_uint64())
    }
    _ => ()
  }
}

///|
/// 比较与逻辑族（压 0/1；无符号四则经 u32 重解释比较）。
fn VitroVM::execute_comparison(
  self : VitroVM,
  op : @opcode.OpCode,
  _operand : Int,
  _line : Int,
  _column : Int,
) -> Unit {
  match op {
    Eq => {
      let b = self.pop_i32()
      let a = self.pop_i32()
      self.push(if a == b { 1UL } else { 0UL })
    }
    Ne => {
      let b = self.pop_i32()
      let a = self.pop_i32()
      self.push(if a != b { 1UL } else { 0UL })
    }
    Lt => {
      let b = self.pop_i32()
      let a = self.pop_i32()
      self.push(if a < b { 1UL } else { 0UL })
    }
    Le => {
      let b = self.pop_i32()
      let a = self.pop_i32()
      self.push(if a <= b { 1UL } else { 0UL })
    }
    Gt => {
      let b = self.pop_i32()
      let a = self.pop_i32()
      self.push(if a > b { 1UL } else { 0UL })
    }
    Ge => {
      let b = self.pop_i32()
      let a = self.pop_i32()
      self.push(if a >= b { 1UL } else { 0UL })
    }
    ULt => {
      let b = self.pop_addr()
      let a = self.pop_addr()
      self.push(if a < b { 1UL } else { 0UL })
    }
    ULe => {
      let b = self.pop_addr()
      let a = self.pop_addr()
      self.push(if a <= b { 1UL } else { 0UL })
    }
    UGt => {
      let b = self.pop_addr()
      let a = self.pop_addr()
      self.push(if a > b { 1UL } else { 0UL })
    }
    UGe => {
      let b = self.pop_addr()
      let a = self.pop_addr()
      self.push(if a >= b { 1UL } else { 0UL })
    }
    And => {
      let b = self.pop_i32()
      let a = self.pop_i32()
      self.push(if a != 0 && b != 0 { 1UL } else { 0UL })
    }
    Or => {
      let b = self.pop_i32()
      let a = self.pop_i32()
      self.push(if a != 0 || b != 0 { 1UL } else { 0UL })
    }
    Not => {
      let a = self.pop_i32()
      self.push(if a != 0 { 0UL } else { 1UL })
    }
    _ => ()
  }
}

///|
/// 位运算族（32 位移位量 0~31 / 64 位 0~63 越界 trap；Q 族按 u64 位模式
/// 与/或/异或，算术右移按 i64 解释、逻辑右移按 u64）。
fn VitroVM::execute_bitwise(
  self : VitroVM,
  op : @opcode.OpCode,
  _operand : Int,
  line : Int,
  column : Int,
) -> Unit {
  match op {
    BitAnd => {
      let b = self.pop_i32()
      let a = self.pop_i32()
      self.push_i32(a & b)
    }
    BitOr => {
      let b = self.pop_i32()
      let a = self.pop_i32()
      self.push_i32(a | b)
    }
    BitXor => {
      let b = self.pop_i32()
      let a = self.pop_i32()
      self.push_i32(a ^ b)
    }
    BitNot => {
      let a = self.pop_i32()
      self.push_i32(a ^ -1)
    }
    Shl => {
      let b = self.pop_i32()
      let a = self.pop_i32()
      if b < 0 || b >= 32 {
        self.trap(
          "Shl 移位量越界：\{b}（必须是 0~31）",
          line,
          column,
        )
      } else {
        self.push_i32(a << b)
      }
    }
    Shr => {
      let b = self.pop_i32()
      let a = self.pop_i32()
      if b < 0 || b >= 32 {
        self.trap(
          "Shr 移位量越界：\{b}（必须是 0~31）",
          line,
          column,
        )
      } else {
        self.push_i32(a >> b)
      }
    }
    LShr => {
      let b = self.pop_i32()
      let a = self.pop_addr()
      if b < 0 || b >= 32 {
        self.trap(
          "LShr 移位量越界：\{b}（必须是 0~31）",
          line,
          column,
        )
      } else {
        self.push((a >> b).to_uint64())
      }
    }
    // E1 B 档：64 位位运算——栈值本就是 u64 位模式，与符号性无关。
    BitAndQ => {
      let b = self.pop()
      let a = self.pop()
      self.push(a & b)
    }
    BitOrQ => {
      let b = self.pop()
      let a = self.pop()
      self.push(a | b)
    }
    BitXorQ => {
      let b = self.pop()
      let a = self.pop()
      self.push(a ^ b)
    }
    BitNotQ => {
      let a = self.pop()
      self.push(a ^ 18446744073709551615UL)
    }
    ShlQ => {
      let b = self.pop_i64()
      let a = self.pop()
      if b < 0L || b >= 64L {
        self.trap(
          "Shl 移位量越界：\{b}（必须是 0~63）",
          line,
          column,
        )
      } else {
        self.push(a << b.to_int())
      }
    }
    ShrQ => {
      let b = self.pop_i64()
      let a = self.pop_i64()
      if b < 0L || b >= 64L {
        self.trap(
          "Shr 移位量越界：\{b}（必须是 0~63）",
          line,
          column,
        )
      } else {
        self.push((a >> b.to_int()).reinterpret_as_uint64())
      }
    }
    LShrQ => {
      let b = self.pop_i64()
      let a = self.pop()
      if b < 0L || b >= 64L {
        self.trap(
          "LShr 移位量越界：\{b}（必须是 0~63）",
          line,
          column,
        )
      } else {
        self.push(a >> b.to_int())
      }
    }
    _ => ()
  }
}
