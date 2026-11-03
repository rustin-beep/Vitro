// 蓝本注记：文内 Rust 源引用（`*.rs` 路径/行号/符号）均为档案态蓝本——tag rust-oracle-freeze（2026-10-05 删区），现为本仓自主基线。

///| L7 执行层·VM 域·executor：**F（f32）/ D（f64）/ Q（i64）三族**
/// （Rust `executor/float.rs` 逐句照搬）。
///
/// **转换契约（探针实证，2026-09-26）**：MoonBit `Double::to_int` =
/// `%f64_to_i32_saturate`（**饱和**语义，与 Rust 语言 `as i32` 转换一致——NaN→0 /
/// inf→±MAX / 2.7→2）；`Int64::to_int` = 低 32 位截断；f32 位模式经
/// `UInt::reinterpret_as_float` / `Float::reinterpret_as_uint`；f64 位模式经
/// `reinterpret_as_double` / `reinterpret_as_uint64`（host 包同款）。
///
/// **浮点除零 IEEE 语义（#163，2026-10-21）**：DivF/DivD 不再 trap——
/// ±inf / NaN 是 C11 Annex F（IEC 60559）的**定义行为**（clang/gcc 默认，
/// 真值锚）；旧显式 `b == 0.0` → 教学 trap 系迁移期照搬 oracle，oracle
/// 退役后失去锚收编。整数除零 trap 维持（int 域 UB 与浮点域 Annex F 是
/// 两个域的标准语义分划，教学护栏不冲突）。比较族 IEEE
/// 精确语义（E1：无 epsilon 容差——容差使 0.1+0.2==0.3 判真，与 Clang
/// golden 矛盾）。
///
/// **Q 族回绕语义与 i32 族不同（对拍契约）**：AddQ/SubQ/MulQ 是
/// `wrapping`（**不 trap**——Rust 同款；i32 族的 Add/Sub/Mul 才是 i64 中转
/// + 教学 trap）；DivQ/ModQ 的 LLONG_MIN/-1 与除零检查照搬。
///
/// **#426 B3' 批 3（2026-11-02）**：Q 族整型算术/比较臂接共享算术核
/// `vitro/engine/arith`（I64/U64 域）——值语义与故障判定由核产出，本文件
/// 只保栈原语形态（位模式逐位不变）与教学 trap 文案；F/D 浮点族与 Cast 族
/// 不接核（无域分叉面）。

///|
fn VitroVM::execute_float(
  self : VitroVM,
  op : @opcode.OpCode,
  operand : Int32,
  line : Int32,
  column : Int32,
) -> Unit {
  match op {
    PushConstF =>
      // f32 位模式经 i32 operand（低 32 位零扩展压栈——位模式无符号语义）
      self.push(operand.reinterpret_as_uint().to_uint64())
    AddF | SubF | MulF => {
      let b = Float::reinterpret_from_uint(self.pop().to_uint())
      let a = Float::reinterpret_from_uint(self.pop().to_uint())
      let r = match op {
        AddF => a + b
        SubF => a - b
        MulF => a * b
        _ => a
      }
      self.push(Float::reinterpret_as_uint(r).to_uint64())
    }
    DivF => {
      let b = Float::reinterpret_from_uint(self.pop().to_uint())
      let a = Float::reinterpret_from_uint(self.pop().to_uint())
      // #163：IEEE 语义（除零 = ±inf/NaN，头注）
      let r = a / b
      self.push(Float::reinterpret_as_uint(r).to_uint64())
    }
    NegF => {
      let a = Float::reinterpret_from_uint(self.pop().to_uint())
      // 一元负（三轮审阅 P1-2：0.0 - a 会丢零符号——0.0-0.0=+0.0 而
      // -0.0f 位 = 0x80000000；与 NegD 的 -a 同形）
      let r = -a
      self.push(Float::reinterpret_as_uint(r).to_uint64())
    }
    EqF | NeF | LtF | LeF | GtF | GeF => {
      let b = Float::reinterpret_from_uint(self.pop().to_uint())
      let a = Float::reinterpret_from_uint(self.pop().to_uint())
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
    CastU2F => {
      // u32 零符号位转 f32（病 31 同族；对照 CastI2F）
      let a = self.pop_addr()
      let r = Float::from_double(a.to_double())
      self.push(Float::reinterpret_as_uint(r).to_uint64())
    }
    CastUQ2F => {
      // u64 位模式无符号转 f32（#345 P1：CastU2F 的 u64 源版——分派在
      // execute_float（F 族）；pop() 即 UInt64 位模式（UDivQ 同款））
      let a = self.pop()
      let r = Float::from_double(a.to_double())
      self.push(Float::reinterpret_as_uint(r).to_uint64())
    }
    CastF2I => {
      let a = Float::reinterpret_from_uint(self.pop().to_uint())
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
  operand : Int32,
  line : Int32,
  column : Int32,
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
      // #163：IEEE 语义（除零 = ±inf/NaN，头注）
      let r = a / b
      self.push(r.reinterpret_as_uint64())
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
    CastU2D => {
      // u32 零符号位转 f64（病 31：(double)3000000000u → 3000000000.0
      // 而非 -1294967296.0——对照 CastI2D 的符号语义）
      let a = self.pop_addr()
      self.push(a.to_double().reinterpret_as_uint64())
    }
    CastUQ2D => {
      // u64 位模式无符号转 f64（#345 审阅 P1，2026-10-28：B17「转换族缺
      // 符号性对偶」补齐——(double)18446744073709551615 旧走 CastQ2D 有
      // 符号解释产 -1；pop() 即 UInt64 位模式（UDivQ 同款），零解释成本）
      let a = self.pop()
      self.push(a.to_double().reinterpret_as_uint64())
    }
    CastF2D => {
      let a = Float::reinterpret_from_uint(self.pop().to_uint())
      self.push(a.to_double().reinterpret_as_uint64())
    }
    CastD2I => {
      let a = self.pop().reinterpret_as_double()
      // 饱和语义（%f64_to_i32_saturate = Rust as i32）
      self.push_i32(a.to_int())
    }
    CastD2F => {
      let a = self.pop().reinterpret_as_double()
      self.push(Float::reinterpret_as_uint(Float::from_double(a)).to_uint64())
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
  operand : Int32,
  line : Int32,
  column : Int32,
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
      // #426 批 3：接共享算术核 I64 域（核语义表镜像本分口径：I64 四则回绕
      // 不产故障）
      let b = self.pop_i64()
      let a = self.pop_i64()
      let aop = match op {
        AddQ => @arith.OpAdd
        SubQ => @arith.OpSub
        _ => @arith.OpMul
      }
      match @arith.eval_int_binary(aop, a, b, @arith.I64) {
        Ok(r) => self.push(r.reinterpret_as_uint64())
        Err(_) => () // I64 四则无故障面（穷尽兜底）
      }
    }
    DivQ => {
      let b = self.pop_i64()
      let a = self.pop_i64()
      match @arith.eval_int_binary(@arith.OpDiv, a, b, @arith.I64) {
        Ok(r) => self.push(r.reinterpret_as_uint64())
        Err(@arith.DivByZero) => {
          // 审阅 P2-1（2026-10-24）：裸文案改教学段（i64 符号渲染）+ 补结构化码
          // ——同族 i32/u32/u64 六臂带码独漏此臂。
          let msg = self.format_div_zero_error_i64(a)
          self.trap(msg, line, column, code="E3088")
        }
        Err(_) =>
          self.trap(
            "long long 除法溢出。LLONG_MIN / -1 的结果超出了 long long 能表示的范围。",
            line, column,
          )
      }
    }
    ModQ => {
      let b = self.pop_i64()
      let a = self.pop_i64()
      match @arith.eval_int_binary(@arith.OpMod, a, b, @arith.I64) {
        Ok(r) => self.push(r.reinterpret_as_uint64())
        Err(@arith.DivByZero) => {
          // 审阅 P2-1 同款：裸文案改教学段 + 补结构化码。
          let msg = self.format_div_zero_error_i64(a)
          self.trap(msg, line, column, code="E3088")
        }
        Err(_) =>
          self.trap(
            "long long 取模溢出。LLONG_MIN % -1 的结果未定义，超出了 long long 能表示的范围。",
            line, column,
          )
      }
    }
    NegQ => {
      let a = self.pop_i64()
      match @arith.eval_int_unary(@arith.OpNeg, a, @arith.I64) {
        Ok(r) => self.push(r.reinterpret_as_uint64())
        Err(_) =>
          self.trap(
            "long long 取反溢出。-LLONG_MIN 的结果超出了 long long 能表示的范围。",
            line, column,
          )
      }
    }
    CastI2Q => {
      let a = self.pop_i32()
      self.push(a.to_int64().reinterpret_as_uint64())
    }
    CastU2Q => {
      // u32 零扩展进 i64（病 31：(long long)4294967295u → 4294967295
      // 而非 -1——对照 CastI2Q 的符号扩展）
      let a = self.pop_addr()
      self.push(a.to_uint64())
    }
    UDivQ => {
      // Q 族无符号除（病 34：ULL 走 DivQ 符号语义 2^63 域错值）；除零
      // 文案走 u64 版（被除数无符号渲染——病 93 同族预防）
      // #426 批 3：接核 U64 域（位模式重解释做无符号除）
      let b = self.pop()
      let a = self.pop()
      match
        @arith.eval_int_binary(
          @arith.OpDiv,
          a.reinterpret_as_int64(),
          b.reinterpret_as_int64(),
          @arith.U64,
        ) {
        Ok(r) => self.push(r.reinterpret_as_uint64())
        Err(_) => {
          let msg = self.format_div_zero_error_u64(a)
          self.trap(msg, line, column, code="E3088")
        }
      }
    }
    UModQ => {
      // Q 族无符号模（无 LLONG_MIN % -1 面——u64 域不存在该溢出）
      let b = self.pop()
      let a = self.pop()
      match
        @arith.eval_int_binary(
          @arith.OpMod,
          a.reinterpret_as_int64(),
          b.reinterpret_as_int64(),
          @arith.U64,
        ) {
        Ok(r) => self.push(r.reinterpret_as_uint64())
        Err(_) => {
          let msg = self.format_div_zero_error_u64(a)
          self.trap(msg, line, column, code="E3088")
        }
      }
    }
    UNegQ => {
      // 无符号取反 = 模 2^64 补（回绕无 trap——对照 NegQ 的教学 trap）
      let a = self.pop()
      match
        @arith.eval_int_unary(
          @arith.OpNeg,
          a.reinterpret_as_int64(),
          @arith.U64,
        ) {
        Ok(r) => self.push(r.reinterpret_as_uint64())
        Err(_) => ()
      }
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
      // #426 批 3：接核 I64 域比较
      let b = self.pop_i64()
      let a = self.pop_i64()
      let aop = match op {
        EqQ => @arith.OpEq
        NeQ => @arith.OpNe
        LtQ => @arith.OpLt
        LeQ => @arith.OpLe
        GtQ => @arith.OpGt
        _ => @arith.OpGe
      }
      match @arith.eval_int_binary(aop, a, b, @arith.I64) {
        Ok(v) => self.push(if v != 0L { 1UL } else { 0UL })
        Err(_) => ()
      }
    }
    ULtQ | ULeQ | UGtQ | UGeQ => {
      // Q 族无符号比较（病 34：2^63 > 0 走 LtQ 符号语义得 0）
      // #426 批 3：接核 U64 域（位模式重解释比较）
      let b = self.pop()
      let a = self.pop()
      let aop = match op {
        ULtQ => @arith.OpLt
        ULeQ => @arith.OpLe
        UGtQ => @arith.OpGt
        _ => @arith.OpGe
      }
      match
        @arith.eval_int_binary(
          aop,
          a.reinterpret_as_int64(),
          b.reinterpret_as_int64(),
          @arith.U64,
        ) {
        Ok(v) => self.push(if v != 0L { 1UL } else { 0UL })
        Err(_) => ()
      }
    }
    _ => ()
  }
}
