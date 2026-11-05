///|
/// 镜像域枚举与求值载体（PROVE-arith 批，2026-11-04）——vitro/engine/arith
/// 的 IntDomain 同名镜像（跨包须限定 @arith.，镜像侧裸名不冲突）。
pub(all) enum IntDomain {
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
/// 求值载体镜像——Result 的 Ok/Err 构造器在 .mlw 层 unbound（moon prove
/// 0.10.18 上游缺口，探针实锤），自定义 Outcome 两态替代。
pub(all) enum Outcome {
  V(Int64) // Ok 值
  F(Fault) // 故障（ArithFault 镜像）
} derive(Eq, Compare, Debug)

///|
pub extend Outcome with Eq::{not_equal, equal}

///|
pub extend Outcome with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend Outcome with Debug::{to_repr}

///|
/// ArithFault 镜像（变体名前加 F 避与 Outcome 构造器混淆；ShiftOutOfRange
/// 携越界移位量原值）。
pub(all) enum Fault {
  FDivByZero
  FDivOverflow
  FShiftOutOfRange(Int64)
  FAddOverflow
  FSubOverflow
  FMulOverflow
  FNegOverflow
} derive(Eq, Compare, Debug)

///|
pub extend Fault with Eq::{not_equal, equal}

///|
pub extend Fault with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend Fault with Debug::{to_repr}

///|
/// 低 32 位无符号回绕模型（U32 域模 2^32 数学形态；4294967296 = 2^32 在
/// Int64 域内——可执行可证双属性）。契约即回绕域完备引理（像集 ⊆ U32 域）。
pub fn wrap32u(
  v : Int64,
) -> Int64 where {
  proof_ensure: result => 0L <= result,
  proof_ensure: result => result <= 4294967295L,
} {
  (v % 4294967296L + 4294967296L) % 4294967296L
}

///|
/// 低 32 位符号解释模型（I32 域回绕——`v << 32 >> 32` 的算术化）。
pub fn wrap32s(
  v : Int64,
) -> Int64 where {
  proof_ensure: result => -2147483648L <= result,
  proof_ensure: result => result <= 2147483647L,
} {
  let u = wrap32u(v)
  if u < 2147483648L {
    u
  } else {
    u - 4294967296L
  }
}

///|
/// 移位量判界镜像返回（shift_guard 的 Ok(s.to_int()) / Err(ShiftOutOfRange(s))
/// 两态——原函数嵌套 fn 不被支持，镜像提为独立类型与顶层函数）。
pub(all) enum ShiftGuardM {
  GOk
  GBad(Int64) // 越界移位量原值（诊断渲染用，同 ShiftOutOfRange）
} derive(Eq, Compare, Debug)

///|
pub extend ShiftGuardM with Eq::{not_equal, equal}

///|
pub extend ShiftGuardM with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend ShiftGuardM with Debug::{to_repr}

///|
/// 2^s 幂表（移位算术化的乘除形态载体）——契约只锁所需最小性质
/// （s ≥ 0 → 2^s ≥ 1：除法收缩性与乘法域完备引理的公共前置）。
/// 运行时域注意：s ≤ 62 域内可执行；s = 63 回绕（对拍样本域排除，见
/// parity_test.mbt 注）。
pub fn two_pow(
  s : Int32,
) -> Int64 where {
  proof_require: 0 <= s,
  proof_ensure: result => result >= 1L,
} {
  let r = for k = 0, acc = 1L; k < s; {
    continue k + 1, acc * 2L
  } nobreak {
    acc
  } where {
    proof_invariant: 0 <= k,
    proof_invariant: k <= s,
    proof_invariant: acc >= 1L,
  }
  r
}

///|
/// 向下取整除（C 算术右移 `l >> s` = floor(l / 2^s)——Int64 `/` 是向零
/// 截断，负被除数须修正 -1）。契约锁值域收缩（p ≥ 1 → 结果夹在 l 与 0
/// 之间）——Shr 各域值域完备的公共引理。
pub fn floor_div_pos(
  l : Int64,
  p : Int64,
) -> Int64 where {
  proof_require: p >= 1L,
  proof_ensure: result => l >= 0L → 0L <= result && result <= l,
  proof_ensure: result => l < 0L → l <= result && result <= 0L,
} {
  let q = l / p
  if l % p != 0L && l < 0L {
    q - 1L
  } else {
    q
  }
}

///|
/// 移位量判界镜像（arith.mbt eval_int_binary 内嵌 shift_guard 的顶层化
/// 镜像；width 按运算域宽 32/64——域宽判界口径照搬）——拒绝路径前置
/// 完备：越界 ⇔ GBad（携带原值）。
pub fn m_shift_guard(
  width : Int64,
  s : Int64,
) -> ShiftGuardM where {
  proof_require: width == 32L || width == 64L,
  proof_ensure: result => {
    match result {
      GOk => 0L <= s && s < width
      GBad(orig) => (s < 0L || s >= width) && orig == s
    }
  },
} {
  if s < 0L || s >= width {
    GBad(s)
  } else {
    GOk
  }
}
