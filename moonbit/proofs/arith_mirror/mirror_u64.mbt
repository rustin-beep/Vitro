///|
/// U64 域可证面镜像（PROVE-arith 契约批）——位模式语义中**容器内可判**的
/// 臂：Div/Mod 的除零拒绝（位模式零 == 容器 0L，语义精确）、Eq/Ne 位模式
/// 相等（容器 == 即位模式 ==）、BitNot 位互补（-1 平移在容器域线性封闭）。
/// **登记不证**（诚实口径，见批报告）：无符号序（Lt/Le/Gt/Ge 的
/// reinterpret_as_uint64 位模式序）、无符号除/模（UDivQ/UModQ 值域）、
/// 逻辑右移、Shl/Add/Sub/Mul/Neg 回绕族——位模式重解释的数学建模需
/// unsign64(x) = x + 2^64（负值侧）超域常量，Int64 载体内不可构造；
/// 域完备由容器类型系统平凡保证。

///|
/// OpDiv→U64 臂·拒绝路径专项镜像（arith.mbt:240-247）：除零 ⇔ 拒绝完备
/// （位模式零判定 = 容器 0L）。**V 路径哨兵值 0L**——无符号商语义
/// （reinterpret_as_uint64 位模式除）的数学建模需 unsign64 超域常量，
/// 不在证明面（body 哨兵与原函数商值不同，登记见文件头注；对拍锚
/// 本臂只对拍拒绝路径，见 parity_test.mbt）。
fn m_div_u64(
  l : Int64,
  r : Int64,
) -> Outcome where {
  proof_require: -9223372036854775808L <= l,
  proof_require: l <= 9223372036854775807L,
  proof_require: -9223372036854775808L <= r,
  proof_require: r <= 9223372036854775807L,
  proof_ensure: result => {
    match result {
      V(v) => r != 0L && -9223372036854775808L <= v && v <= 9223372036854775807L
      F(f) =>
        match f {
          FDivByZero => r == 0L
          _ => false
        }
    }
  },
} {
  if r == 0L {
    F(FDivByZero)
  } else {
    V(0L)
  }
}

///|
/// OpMod→U64 臂·拒绝路径专项镜像（arith.mbt:269-276）：除零 ⇔ 拒绝完备
/// （无 MIN/-1 面——无符号域不存在该溢出，VM UModQ 注释同款口径）。
/// V 路径哨兵同 m_div_u64 头注。
fn m_mod_u64(
  l : Int64,
  r : Int64,
) -> Outcome where {
  proof_require: -9223372036854775808L <= l,
  proof_require: l <= 9223372036854775807L,
  proof_require: -9223372036854775808L <= r,
  proof_require: r <= 9223372036854775807L,
  proof_ensure: result => {
    match result {
      V(v) => r != 0L && -9223372036854775808L <= v && v <= 9223372036854775807L
      F(f) =>
        match f {
          FDivByZero => r == 0L
          _ => false
        }
    }
  },
} {
  if r == 0L {
    F(FDivByZero)
  } else {
    V(0L)
  }
}

///|
/// OpEq→U64 臂（arith.mbt:302）：位模式相等 = 容器相等。
fn m_eq_u64(
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

///|
/// OpBitNot→U64 臂（arith.mbt:341 U64 => Ok(-1L - v)）：位互补的容器域
/// 封闭（-1 平移线性）。
fn m_bitnot_u64(
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
