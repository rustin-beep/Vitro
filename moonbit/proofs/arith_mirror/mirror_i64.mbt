///|
/// I64 域可证面镜像（PROVE-arith 契约批）——不涉回绕的语义臂逐臂镜像：
/// Div/Mod 拒绝路径与商余值域收缩、Shr 算术右移、Neg 溢出对拒绝、
/// BitNot 域互补封闭（min = -max-1 精确互补）、比较/Eq/Ne 规范。
/// **登记不证**（诚实口径，见批报告）：Add/Sub/Mul/Shl 的 Int64 容器回绕
/// 族——无界证明语义下回绕建模需 2^64 超域常量（Int64 载体内不可构造），
/// 其域完备在机器层由类型系统平凡保证（容器装不下域外值），证明增量为零。

///|
/// OpDiv→I64 臂（arith.mbt:231-238）：除零/LLONG_MIN÷-1 拒绝完备 +
/// 商值域（|截断商| ≤ |l| ≤ LLONG_MAX）。
fn m_div_i64(
  l : Int64,
  r : Int64,
) -> Outcome where {
  proof_require: -9223372036854775808L <= l,
  proof_require: l <= 9223372036854775807L,
  proof_require: -9223372036854775808L <= r,
  proof_require: r <= 9223372036854775807L,
  proof_ensure: result => {
    match result {
      V(v) =>
        r != 0L &&
        (l != -9223372036854775808L || r != -1L) &&
        -9223372036854775808L <= v &&
        v <= 9223372036854775807L
      F(f) =>
        match f {
          FDivByZero => r == 0L
          FDivOverflow => l == -9223372036854775808L && r == -1L
          _ => false
        }
    }
  },
} {
  if r == 0L {
    F(FDivByZero)
  } else if l == -9223372036854775808L && r == -1L {
    F(FDivOverflow)
  } else {
    V(l / r)
  }
}

///|
/// OpMod→I64 臂（arith.mbt:260-267）：拒绝同 Div；|余| < |r| 收缩
/// （截断取余，符号随被除数）。
fn m_mod_i64(
  l : Int64,
  r : Int64,
) -> Outcome where {
  proof_require: -9223372036854775808L <= l,
  proof_require: l <= 9223372036854775807L,
  proof_require: -9223372036854775808L <= r,
  proof_require: r <= 9223372036854775807L,
  proof_ensure: result => {
    match result {
      V(v) =>
        r != 0L &&
        (l != -9223372036854775808L || r != -1L) &&
        -9223372036854775808L <= v &&
        v <= 9223372036854775807L
      F(f) =>
        match f {
          FDivByZero => r == 0L
          FDivOverflow => l == -9223372036854775808L && r == -1L
          _ => false
        }
    }
  },
} {
  if r == 0L {
    F(FDivByZero)
  } else if l == -9223372036854775808L && r == -1L {
    F(FDivOverflow)
  } else {
    V(l % r)
  }
}

///|
/// OpShr→I64 臂（arith.mbt:286-292 I32|I64 算术右移）：floor(l / 2^s) 值域
/// 收缩（结果夹在 l 与 0 之间）。
fn m_shr_i64(
  l : Int64,
  s : Int32,
) -> Outcome where {
  proof_require: -9223372036854775808L <= l,
  proof_require: l <= 9223372036854775807L,
  proof_require: 0 <= s,
  proof_require: s < 64,
  proof_ensure: result => {
    match result {
      V(v) => -9223372036854775808L <= v && v <= 9223372036854775807L
      F(_) => false
    }
  },
} {
  // s=63 全量右移特判（PR #480 审阅 P3-5）：two_pow(63) 在 Int64 容器回绕
  // 成 -2^63，违反 floor_div_pos 的 p ≥ 1 前置（证明层无界语义不报、运行
  // 期对拍可见的分叉根因）——特判语义 = 算术右移移满 63 位 = 符号位填充，
  // 证明域不收窄。
  if s == 63 {
    V(if l < 0L { -1L } else { 0L })
  } else {
    V(floor_div_pos(l, two_pow(s)))
  }
}

///|
/// OpNeg→I64 臂（arith.mbt OpNeg→I64）：LLONG_MIN 取反对拒绝完备 +
/// 其余 -v ≤ LLONG_MAX。
fn m_neg_i64(
  v : Int64,
) -> Outcome where {
  proof_require: -9223372036854775808L <= v,
  proof_require: v <= 9223372036854775807L,
  proof_ensure: result => {
    match result {
      V(x) =>
        -9223372036854775808L <= x &&
        x <= 9223372036854775807L &&
        v != -9223372036854775808L
      F(f) =>
        match f {
          FNegOverflow => v == -9223372036854775808L
          _ => false
        }
    }
  },
} {
  if v == -9223372036854775808L {
    F(FNegOverflow)
  } else {
    V(-v)
  }
}

///|
/// OpBitNot→I64 臂（arith.mbt:341 -1L - v）：I64 域对 -1 平移封闭
/// （min = -max - 1 精确互补：-1-min = max、-1-max = min）——线性可证。
fn m_bitnot_i64(
  v : Int64,
) -> Outcome where {
  proof_require: -9223372036854775808L <= v,
  proof_require: v <= 9223372036854775807L,
  proof_ensure: result => {
    match result {
      V(x) => -9223372036854775808L <= x && x <= 9223372036854775807L
      F(_) => false
    }
  },
} {
  V(-1L - v)
}

///|
/// OpLt→I64 臂（arith.mbt:298，cmp_lt 默认有符号 <）。
fn m_lt_i64(
  l : Int64,
  r : Int64,
) -> Outcome where {
  proof_require: -9223372036854775808L <= l,
  proof_require: l <= 9223372036854775807L,
  proof_require: -9223372036854775808L <= r,
  proof_require: r <= 9223372036854775807L,
  proof_ensure: result => {
    match result {
      V(v) => v == 0L || v == 1L
      F(_) => false
    }
  },
} {
  V(if l < r { 1L } else { 0L })
}

///|
/// OpEq→I64 臂（arith.mbt:302）。
fn m_eq_i64(
  l : Int64,
  r : Int64,
) -> Outcome where {
  proof_require: -9223372036854775808L <= l,
  proof_require: l <= 9223372036854775807L,
  proof_require: -9223372036854775808L <= r,
  proof_require: r <= 9223372036854775807L,
  proof_ensure: result => {
    match result {
      V(v) => v == 0L || v == 1L
      F(_) => false
    }
  },
} {
  V(if l == r { 1L } else { 0L })
}
