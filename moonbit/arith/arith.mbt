///|
/// 共享算术核（#426 B3' 批 0，2026-11-02）——常量折叠器与 VM 执行器的
/// C 整型算术语义单源。设计单：docs/current/07-质量与裁定/常量折叠共享算术核设计单.md。
///
/// **值约定**：核值一律 Int64 容器装**运算域规范值**——
/// I32 = 符号扩展的 i32（-2^31..2^31-1）/ U32 = 零扩展（0..2^32-1）/
/// I64 = 本身 / U64 = 位模式（UInt64 重解释）。调用方先 `normalize`
/// 操作数到运算域，核返回值即规范值（比较 0/1 除外），无需二次归一。
///
/// **域分划契约（语义表 = VM 现状镜像）**：
/// - I32 有符号 Add/Sub/Mul/Neg 溢出 → 故障（VM i32 族教学 trap 口径，
///   exec_arith.mbt 镜像）；U32/I64/U64 四则回绕（VM U* 族与 Q 族镜像，
///   exec_float.mbt「Q 族回绕」头注）——两口径分划系既有对拍契约裁定，
///   本核继承不重裁。
/// - Div/Mod 全域除零 + I32 的 INT_MIN/-1 + I64 的 LLONG_MIN/-1 → 故障
///   （UB 域，VM 教学口径 trap）；U 域无 MIN/-1 面。
/// - 移位量按**运算域宽**判界（I32/U32: 0~31，I64/U64: 0~63），负数同拒
///   （VM Shl/Shr/LShr/Q 族镜像）。注意：Shl/Shr 的 dom 须传**左操作数
///   提升后域**（C11 §6.5.7 结果符号性随左操作数），与 Div/比较的公共
///   域不同源——该分划由调用方负责传对（设计单 §二·2 要点 1）。
/// - Eq/Ne 同域规范后按位模式比较（M08 A2 的核内解）。
///
/// **不进核的面**（登记，防边界漂移）：AST 解析与短路求值（&&/|| 是树
/// 结构语义——折叠器栈机层仿 codegen binary.mbt 短路结构做）；trap 文案
/// 与诊断码（消费方资产）；char 8 位域（折叠器 cast 面本地截断，现状正确）；
/// 浮→整的 U32/U64 目标域（UB/C23 域，登记不修——设计单 §五·4）；浮点
/// 四则/比较（VM F/D 族无域分叉面，现状单源已够）。

///|
/// 整型运算域（char/uchar 经 integer_promote 后不再出现——C11 §6.3.1.1
/// 整型提升，unsigned 位随提升消失）。
pub enum IntDomain {
  I32
  U32
  I64
  U64
} derive(Eq, Compare, Debug)

///|
pub extend IntDomain with Eq::{not_equal, equal}

///|
pub extend IntDomain with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend IntDomain with Debug::{to_repr}

///|
/// C 整型 kind（教学 C 子集三档宽度）——AST Type 到 IntDomain 薄壳
/// 映射的输入（typeck 侧查表两行，核不 import ast）。
pub enum IntKind {
  KChar
  KInt
  KLongLong
} derive(Eq, Compare, Debug)

///|
pub extend IntKind with Eq::{not_equal, equal}

///|
pub extend IntKind with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend IntKind with Debug::{to_repr}

///|
/// 算术故障——核不定策略，消费方翻译：VM → 教学 trap 文案（E3088 族/
/// 溢出文案）；折叠器 → E3075 族诊断（除零/移位/Div 溢出）或 W 级溢出
/// 警告（Add/Sub/Mul/Neg 溢出，#426 拍板①：W 级照折对齐 clang
/// -Winteger-overflow）。
pub enum ArithFault {
  DivByZero
  DivOverflow // INT_MIN/-1（I32）/ LLONG_MIN/-1（I64）——UB 域，两侧同故障
  ShiftOutOfRange(Int64) // 越界移位量原值随故障带回（诊断渲染用）
  AddOverflow // 以下四项仅 I32 域产（教学 trap 口径）；U32/I64/U64 回绕不产
  SubOverflow
  MulOverflow
  NegOverflow
} derive(Eq, Compare, Debug)

///|
pub extend ArithFault with Eq::{not_equal, equal}

///|
pub extend ArithFault with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend ArithFault with Debug::{to_repr}

///|
/// 整型二元算子（16）。
pub enum IntBinOp {
  OpAdd
  OpSub
  OpMul
  OpDiv
  OpMod
  OpBitAnd
  OpBitOr
  OpBitXor
  OpShl
  OpShr
  OpLt
  OpLe
  OpGt
  OpGe
  OpEq
  OpNe
}

///|
/// 整型一元算子（2）。
pub enum IntUnOp {
  OpNeg
  OpBitNot
}

///|
/// C11 §6.3.1.1 整型提升：char 系 → I32（**unsigned 位消失**——int 装得下
/// 其全值域，M08 A7.1/A7.3 的修复锚点）；int/long long 不动（保符号位）。
pub fn integer_promote(kind : IntKind, is_unsigned : Bool) -> IntDomain {
  match kind {
    KChar => I32
    KInt => if is_unsigned { U32 } else { I32 }
    KLongLong => if is_unsigned { U64 } else { I64 }
  }
}

///|
/// C11 §6.3.1.8 usual arithmetic conversions（提升后两侧的公共域）——
/// typeck promote_type（expr.mbt 病 30 修）的值域面孪生，16 格穷尽：
/// 同 rank 任一 unsigned 即无符号域；跨 rank 取高 rank 域
///（I64 全值域 ⊇ U32 → signed I64 胜出——M08 A1 的修复锚点；
/// U64 ⊄ I64 → U64）。
pub fn common_domain(l : IntDomain, r : IntDomain) -> IntDomain {
  match (l, r) {
    // 同 rank（I32 档）
    (I32, I32) => I32
    (I32, U32) | (U32, I32) | (U32, U32) => U32
    // 同 rank（I64 档）
    (I64, I64) => I64
    (I64, U64) | (U64, I64) | (U64, U64) => U64
    // 跨 rank：高 rank 域胜（保其符号位）
    (I64, I32) | (I64, U32) | (I32, I64) | (U32, I64) => I64
    (U64, I32) | (U64, U32) | (I32, U64) | (U32, U64) => U64
  }
}

///|
/// 值按域归一：I32 低 32 位符号扩展 / U32 低 32 位零扩展 / I64·U64 不动。
///（const_eval ce_normalize 的核版；VM 侧 pop_i32/pop_addr 的隐式同构。）
pub fn normalize(v : Int64, dom : IntDomain) -> Int64 {
  match dom {
    I32 => v << 32 >> 32
    U32 => v & 0xFFFFFFFFL
    I64 | U64 => v
  }
}

///|
/// 整型二元求值单点（语义表 = VM 现状镜像，模块头注域分划契约）。
/// l/r 须已 normalize 到 dom（Shl/Shr 见头注——dom 为左操作数提升后域）。
pub fn eval_int_binary(
  op : IntBinOp,
  l : Int64,
  r : Int64,
  dom : IntDomain,
) -> Result[Int64, ArithFault] {
  fn shift_guard(dom_ : IntDomain, s : Int64) -> Result[Int32, ArithFault] {
    let width = match dom_ {
      I32 | U32 => 32
      I64 | U64 => 64
    }
    if s < 0L || s >= width.to_int64() {
      Err(ShiftOutOfRange(s))
    } else {
      Ok(s.to_int())
    }
  }
  match op {
    OpAdd =>
      match dom {
        I32 => {
          let v = l + r
          if v > 2147483647L || v < -2147483648L {
            Err(AddOverflow)
          } else {
            Ok(v)
          }
        }
        U32 => Ok(normalize(l + r, U32))
        I64 | U64 => Ok(l + r) // Int64 容器四则静默回绕（F1 实证，Q 族镜像）
      }
    OpSub =>
      match dom {
        I32 => {
          let v = l - r
          if v > 2147483647L || v < -2147483648L {
            Err(SubOverflow)
          } else {
            Ok(v)
          }
        }
        U32 => Ok(normalize(l - r, U32))
        I64 | U64 => Ok(l - r)
      }
    OpMul =>
      match dom {
        I32 => {
          let v = l * r
          if v > 2147483647L || v < -2147483648L {
            Err(MulOverflow)
          } else {
            Ok(v)
          }
        }
        U32 => Ok(normalize(l * r, U32))
        I64 | U64 => Ok(l * r)
      }
    OpDiv =>
      match dom {
        I32 =>
          if r == 0L {
            Err(DivByZero)
          } else if l == -2147483648L && r == -1L {
            Err(DivOverflow)
          } else {
            Ok(l / r)
          }
        U32 => if r == 0L { Err(DivByZero) } else { Ok(l / r) }
        I64 =>
          if r == 0L {
            Err(DivByZero)
          } else if l == -9223372036854775808L && r == -1L {
            Err(DivOverflow)
          } else {
            Ok(l / r)
          }
        // U64：位模式重解释做无符号除（VM UDivQ 镜像）
        U64 =>
          if r == 0L {
            Err(DivByZero)
          } else {
            Ok(
              (l.reinterpret_as_uint64() / r.reinterpret_as_uint64()).reinterpret_as_int64(),
            )
          }
      }
    OpMod =>
      match dom {
        I32 =>
          if r == 0L {
            Err(DivByZero)
          } else if l == -2147483648L && r == -1L {
            Err(DivOverflow)
          } else {
            Ok(l % r)
          }
        U32 => if r == 0L { Err(DivByZero) } else { Ok(l % r) }
        I64 =>
          if r == 0L {
            Err(DivByZero)
          } else if l == -9223372036854775808L && r == -1L {
            Err(DivOverflow)
          } else {
            Ok(l % r)
          }
        // U64 无 MIN/-1 面（无符号域不存在该溢出——VM UModQ 注释同款）
        U64 =>
          if r == 0L {
            Err(DivByZero)
          } else {
            Ok(
              (l.reinterpret_as_uint64() % r.reinterpret_as_uint64()).reinterpret_as_int64(),
            )
          }
      }
    OpBitAnd => Ok(l & r) // 位模式运算域封闭：I32 符号位与符号位、U32 高位恒 0
    OpBitOr => Ok(l | r)
    OpBitXor => Ok(l ^ r)
    OpShl =>
      match shift_guard(dom, r) {
        Err(f) => Err(f)
        Ok(s) => Ok(normalize(l << s, dom)) // I32 截 32 位（VM Shl 镜像）；I64/U64 不动
      }
    OpShr =>
      match shift_guard(dom, r) {
        Err(f) => Err(f)
        Ok(s) =>
          match dom {
            // 算术右移（I32 规范值已符号扩展，Int64 >> 保持；I64 同）
            I32 | I64 => Ok(l >> s)
            // 逻辑右移（U32 规范值恒正，Int64 >> 即逻辑；U64 位模式重解释）
            U32 => Ok(l >> s)
            U64 => Ok((l.reinterpret_as_uint64() >> s).reinterpret_as_int64())
          }
      }
    OpLt => Ok(if cmp_lt(l, r, dom) { 1L } else { 0L })
    OpLe => Ok(if cmp_lt(r, l, dom) { 0L } else { 1L })
    OpGt => Ok(if cmp_lt(r, l, dom) { 1L } else { 0L })
    OpGe => Ok(if cmp_lt(l, r, dom) { 0L } else { 1L })
    OpEq => Ok(if l == r { 1L } else { 0L }) // 同域规范值位模式相等（A2 解）
    OpNe => Ok(if l != r { 1L } else { 0L })
  }
}

///|
/// U64 位模式比较，其余域规范值直接比（I32/I64 有符号、U32 恒正）。
fn cmp_lt(l : Int64, r : Int64, dom : IntDomain) -> Bool {
  match dom {
    U64 => l.reinterpret_as_uint64() < r.reinterpret_as_uint64()
    _ => l < r
  }
}

///|
/// 整型一元求值（Neg 取反 / BitNot 按位非，按域）。
pub fn eval_int_unary(
  op : IntUnOp,
  v : Int64,
  dom : IntDomain,
) -> Result[Int64, ArithFault] {
  match op {
    OpNeg =>
      match dom {
        I32 => if v == -2147483648L { Err(NegOverflow) } else { Ok(-v) }
        U32 => Ok(normalize(0L - v, U32)) // 模 2^32 补（VM UNeg 镜像）
        I64 =>
          if v == -9223372036854775808L {
            Err(NegOverflow)
          } else {
            Ok(-v)
          }
        U64 => Ok(0L - v) // 模 2^64 补（位模式回绕，VM UNegQ 镜像）
      }
    OpBitNot =>
      // 二补码代数式 ~v = -v - 1；I32 域封闭（-1-INT_MIN=INT_MAX）、
      // U32 截 32 位零扩展、I64/U64 位模式同式
      match dom {
        U32 => Ok(normalize(-1L - v, U32))
        I32 | I64 | U64 => Ok(-1L - v)
      }
  }
}

///|
/// f64 → int32 **饱和**转换（NaN→0 / ±inf→±INT_MAX / 2.7→2 / 1e10→
/// 2147483647）——MoonBit `Double::to_int` 实证口径（= Rust `as i32`，
/// VM CastD2I/CastF2I 镜像）。M08 A5 修复锚点：`(int)1e300` 折叠与运行期
/// 同源走此函数（旧路径 to_int64 饱和到 i64 max 再截低 32 位 = -1 错值）。
pub fn f2i_saturate_i32(f : Double) -> Int64 {
  f.to_int().to_int64()
}

///|
/// f64 → int64 饱和转换（同族口径：MoonBit `Double::to_int64` 饱和实现，
/// VM CastD2Q 镜像）。
pub fn f2i_saturate_i64(f : Double) -> Int64 {
  f.to_int64()
}
