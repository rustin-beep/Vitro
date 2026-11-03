// 蓝本注记：文内 Rust 源引用（`*.rs` 路径/行号/符号）均为档案态蓝本——tag rust-oracle-freeze（2026-10-05 删区），现为本仓自主基线。

///| L7 执行层·VM 域·executor：**算术 / 比较 / 位运算族**（Rust
/// `executor/arithmetic.rs` 逐句照搬）。
///
/// 溢出语义（§0 纠正过的口径，对拍契约）：`Add/Sub/Mul/Neg` 有符号族走
/// i64 中间值 + 范围检查 → **教学 trap**；`U*` 无符号族回绕（MoonBit `Int`
/// 四则静默回绕 = Rust `wrapping_*` 同语义，F1）；`Div/Mod` 的
/// `INT_MIN / -1` 先拦截（Rust `%` panic 击穿 FFI 的事故防御——坑 8）。
///
/// **#426 B3' 批 3（2026-11-02）：整型算术臂接共享算术核 `vitro/engine/arith`**
/// ——值语义与故障判定全部由核产出（与 typeck/const_eval 折叠器同源，静态
/// 与运行期不再各写一遍）；本文件只保留三件 VM 资产：①栈原语形态逐臂
/// 保形（`pop_i32`/`pop_addr` → `push_i32`/`push`，栈槽位模式逐位不变——
/// protocol golden 锁栈内容）②教学 trap 文案（核故障 → 原文案逐字）
/// ③opcode → (核算子, 域) 映射。核语义表 = 本文件接核前行为的镜像
///（arith_wbtest「VM 镜像」锚组逐格锁定），本批验收 = 全 golden 零重冻。

///|
/// i32 语义二元臂骨架：pop_i32 ×2 → 核（dom 由臂指定：有符号族 I32 /
/// `U*` 回绕族 U32——位模式同、仅故障面不同）→ Ok 则 push_i32（截低 32
/// 位再符号扩展 = 原臂 Int32 回绕语义逐位）；Err 交回调用臂渲染文案。
fn VitroVM::arith_i32(
  self : VitroVM,
  op : @arith.IntBinOp,
  dom : @arith.IntDomain,
) -> (Int32, Int32, Result[Int64, @arith.ArithFault]) {
  let b = self.pop_i32()
  let a = self.pop_i32()
  let r = @arith.eval_int_binary(
    op,
    @arith.normalize(a.to_int64(), dom),
    @arith.normalize(b.to_int64(), dom),
    dom,
  )
  (a, b, r)
}

///|
/// u32 语义二元臂骨架：pop_addr ×2（零扩展进核）→ Ok 则 `push` 零扩展位模式
///（原臂 `push((a op b).to_uint64())` 逐位）。
fn VitroVM::arith_u32(
  self : VitroVM,
  op : @arith.IntBinOp,
) -> (UInt32, UInt32, Result[Int64, @arith.ArithFault]) {
  let b = self.pop_addr()
  let a = self.pop_addr()
  let r = @arith.eval_int_binary(
    op,
    a.to_uint64().reinterpret_as_int64(),
    b.to_uint64().reinterpret_as_int64(),
    @arith.U32,
  )
  (a, b, r)
}

///|
fn VitroVM::execute_arithmetic(
  self : VitroVM,
  op : @opcode.OpCode,
  _operand : Int32,
  line : Int32,
  column : Int32,
) -> Unit {
  match op {
    Add =>
      match self.arith_i32(@arith.OpAdd, @arith.I32) {
        (_, _, Ok(r)) => self.push_i32(r.to_int())
        (_, _, Err(_)) =>
          self.trap(
            "整数加法溢出。两个很大的正数（或很小的负数）相加超出了 int 能表示的范围。",
            line, column,
          )
      }
    UAdd =>
      match self.arith_i32(@arith.OpAdd, @arith.U32) {
        (_, _, Ok(r)) => self.push_i32(r.to_int())
        (_, _, Err(_)) => () // U32 域无故障面（穷尽兜底）
      }
    Sub =>
      match self.arith_i32(@arith.OpSub, @arith.I32) {
        (_, _, Ok(r)) => self.push_i32(r.to_int())
        (_, _, Err(_)) =>
          self.trap(
            "整数减法溢出。被减数太小而减数太大，结果超出了 int 能表示的范围。",
            line, column,
          )
      }
    USub =>
      match self.arith_i32(@arith.OpSub, @arith.U32) {
        (_, _, Ok(r)) => self.push_i32(r.to_int())
        (_, _, Err(_)) => ()
      }
    Mul =>
      match self.arith_i32(@arith.OpMul, @arith.I32) {
        (_, _, Ok(r)) => self.push_i32(r.to_int())
        (_, _, Err(_)) =>
          self.trap(
            "整数乘法溢出。乘积太大，超出了 int 能表示的范围。",
            line, column,
          )
      }
    UMul =>
      match self.arith_i32(@arith.OpMul, @arith.U32) {
        (_, _, Ok(r)) => self.push_i32(r.to_int())
        (_, _, Err(_)) => ()
      }
    Div =>
      match self.arith_i32(@arith.OpDiv, @arith.I32) {
        (_, _, Ok(r)) => self.push_i32(r.to_int())
        (a, _, Err(@arith.DivByZero)) => {
          let msg = self.format_div_zero_error(a)
          self.trap(msg, line, column, code="E3088")
        }
        (_, _, Err(_)) =>
          self.trap(
            "整数除法溢出。INT_MIN / -1 的结果超出了 int 能表示的范围。",
            line, column,
          )
      }
    UDiv =>
      match self.arith_u32(@arith.OpDiv) {
        (_, _, Ok(r)) => self.push(r.reinterpret_as_uint64())
        (a, _, Err(_)) => {
          let msg = self.format_div_zero_error(a.reinterpret_as_int())
          self.trap(msg, line, column, code="E3088")
        }
      }
    Mod =>
      match self.arith_i32(@arith.OpMod, @arith.I32) {
        (_, _, Ok(r)) => self.push_i32(r.to_int())
        (a, _, Err(@arith.DivByZero)) => {
          let msg = self.format_div_zero_error(a)
          self.trap(msg, line, column, code="E3088")
        }
        // INT_MIN % -1 未定义——先拦截（坑 8：Rust % 在此处 panic）
        (_, _, Err(_)) =>
          self.trap(
            "整数取模溢出。INT_MIN % -1 的结果未定义，超出了 int 能表示的范围。",
            line, column,
          )
      }
    UMod =>
      match self.arith_u32(@arith.OpMod) {
        (_, _, Ok(r)) => self.push(r.reinterpret_as_uint64())
        (a, _, Err(_)) => {
          let msg = self.format_div_zero_error(a.reinterpret_as_int())
          self.trap(msg, line, column, code="E3088")
        }
      }
    Neg => {
      let a = self.pop_i32()
      match @arith.eval_int_unary(@arith.OpNeg, a.to_int64(), @arith.I32) {
        Ok(r) => self.push_i32(r.to_int())
        Err(_) =>
          self.trap(
            "整数取反溢出。-INT_MIN 的结果超出了 int 能表示的范围。",
            line, column,
          )
      }
    }
    UNeg => {
      let a = self.pop_addr()
      match
        @arith.eval_int_unary(
          @arith.OpNeg,
          a.to_uint64().reinterpret_as_int64(),
          @arith.U32,
        ) {
        Ok(r) => self.push(r.reinterpret_as_uint64())
        Err(_) => ()
      }
    }
    TruncByte => {
      // char 窄化截断（病 33）：低 8 位符号解释（char c=200 读回 -56）；
      // 64 位来源由发射侧先 CastQ2I 再入本臂
      let a = self.pop_i32()
      let b = a & 0xFF
      self.push_i32(if b >= 128 { b - 256 } else { b })
    }
    TruncUByte => {
      // unsigned char 窄化截断（病 33 同族）：低 8 位零扩展（300 → 44）
      let a = self.pop_i32()
      self.push_i32(a & 0xFF)
    }
    _ => ()
  }
}

///|
/// 比较与逻辑族（压 0/1；无符号四则经 u32 重解释比较）。
/// #426 批 3：比较臂接核（I32 有符号 / U32 无符号域）；And/Or/Not 是 codegen
/// 短路结构下的不可达占位（binary.mbt:378-380 自注），保持原形不接核。
fn VitroVM::execute_comparison(
  self : VitroVM,
  op : @opcode.OpCode,
  _operand : Int32,
  _line : Int32,
  _column : Int32,
) -> Unit {
  fn push_bool(vm : VitroVM, r : Result[Int64, @arith.ArithFault]) -> Unit {
    match r {
      Ok(v) => vm.push(if v != 0L { 1UL } else { 0UL })
      Err(_) => () // 比较无故障面（穷尽兜底）
    }
  }
  match op {
    Eq => push_bool(self, self.arith_i32(@arith.OpEq, @arith.I32).2)
    Ne => push_bool(self, self.arith_i32(@arith.OpNe, @arith.I32).2)
    Lt => push_bool(self, self.arith_i32(@arith.OpLt, @arith.I32).2)
    Le => push_bool(self, self.arith_i32(@arith.OpLe, @arith.I32).2)
    Gt => push_bool(self, self.arith_i32(@arith.OpGt, @arith.I32).2)
    Ge => push_bool(self, self.arith_i32(@arith.OpGe, @arith.I32).2)
    ULt => push_bool(self, self.arith_u32(@arith.OpLt).2)
    ULe => push_bool(self, self.arith_u32(@arith.OpLe).2)
    UGt => push_bool(self, self.arith_u32(@arith.OpGt).2)
    UGe => push_bool(self, self.arith_u32(@arith.OpGe).2)
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
/// #426 批 3：全部接核——移位越界判界由核按域宽产 ShiftOutOfRange，臂只
/// 渲染原文案；Q 族位运算走 U64 域（位模式运算与符号无关）。
fn VitroVM::execute_bitwise(
  self : VitroVM,
  op : @opcode.OpCode,
  _operand : Int32,
  line : Int32,
  column : Int32,
) -> Unit {
  match op {
    BitAnd =>
      match self.arith_i32(@arith.OpBitAnd, @arith.I32) {
        (_, _, Ok(r)) => self.push_i32(r.to_int())
        (_, _, Err(_)) => ()
      }
    BitOr =>
      match self.arith_i32(@arith.OpBitOr, @arith.I32) {
        (_, _, Ok(r)) => self.push_i32(r.to_int())
        (_, _, Err(_)) => ()
      }
    BitXor =>
      match self.arith_i32(@arith.OpBitXor, @arith.I32) {
        (_, _, Ok(r)) => self.push_i32(r.to_int())
        (_, _, Err(_)) => ()
      }
    BitNot => {
      let a = self.pop_i32()
      match @arith.eval_int_unary(@arith.OpBitNot, a.to_int64(), @arith.I32) {
        Ok(r) => self.push_i32(r.to_int())
        Err(_) => ()
      }
    }
    Shl =>
      match self.arith_i32(@arith.OpShl, @arith.I32) {
        (_, _, Ok(r)) => self.push_i32(r.to_int())
        (_, b, Err(_)) =>
          self.trap(
            "Shl 移位量越界：\{b}（必须是 0~31）",
            line,
            column,
          )
      }
    Shr =>
      match self.arith_i32(@arith.OpShr, @arith.I32) {
        (_, _, Ok(r)) => self.push_i32(r.to_int())
        (_, b, Err(_)) =>
          self.trap(
            "Shr 移位量越界：\{b}（必须是 0~31）",
            line,
            column,
          )
      }
    LShr => {
      // 左操作数 u32 位模式（pop_addr）、移位量 i32（原臂形态保形）
      let b = self.pop_i32()
      let a = self.pop_addr()
      match
        @arith.eval_int_binary(
          @arith.OpShr,
          a.to_uint64().reinterpret_as_int64(),
          b.to_int64(),
          @arith.U32,
        ) {
        Ok(r) => self.push(r.reinterpret_as_uint64())
        Err(_) =>
          self.trap(
            "LShr 移位量越界：\{b}（必须是 0~31）",
            line,
            column,
          )
      }
    }
    // E1 B 档：64 位位运算——栈值本就是 u64 位模式，与符号性无关。
    BitAndQ => self.bitq(@arith.OpBitAnd)
    BitOrQ => self.bitq(@arith.OpBitOr)
    BitXorQ => self.bitq(@arith.OpBitXor)
    BitNotQ => {
      let a = self.pop()
      match
        @arith.eval_int_unary(
          @arith.OpBitNot,
          a.reinterpret_as_int64(),
          @arith.U64,
        ) {
        Ok(r) => self.push(r.reinterpret_as_uint64())
        Err(_) => ()
      }
    }
    ShlQ => {
      let b = self.pop_i64()
      let a = self.pop()
      match
        @arith.eval_int_binary(
          @arith.OpShl,
          a.reinterpret_as_int64(),
          b,
          @arith.U64,
        ) {
        Ok(r) => self.push(r.reinterpret_as_uint64())
        Err(_) =>
          self.trap(
            "Shl 移位量越界：\{b}（必须是 0~63）",
            line,
            column,
          )
      }
    }
    ShrQ => {
      let b = self.pop_i64()
      let a = self.pop_i64()
      match @arith.eval_int_binary(@arith.OpShr, a, b, @arith.I64) {
        Ok(r) => self.push(r.reinterpret_as_uint64())
        Err(_) =>
          self.trap(
            "Shr 移位量越界：\{b}（必须是 0~63）",
            line,
            column,
          )
      }
    }
    LShrQ => {
      let b = self.pop_i64()
      let a = self.pop()
      match
        @arith.eval_int_binary(
          @arith.OpShr,
          a.reinterpret_as_int64(),
          b,
          @arith.U64,
        ) {
        Ok(r) => self.push(r.reinterpret_as_uint64())
        Err(_) =>
          self.trap(
            "LShr 移位量越界：\{b}（必须是 0~63）",
            line,
            column,
          )
      }
    }
    _ => ()
  }
}

///|
/// Q 族位运算骨架（pop ×2 u64 → 核 U64 → push 位模式）。
fn VitroVM::bitq(self : VitroVM, op : @arith.IntBinOp) -> Unit {
  let b = self.pop()
  let a = self.pop()
  match
    @arith.eval_int_binary(
      op,
      a.reinterpret_as_int64(),
      b.reinterpret_as_int64(),
      @arith.U64,
    ) {
    Ok(r) => self.push(r.reinterpret_as_uint64())
    Err(_) => ()
  }
}
