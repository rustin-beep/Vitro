///|
/// I32 域全算子镜像（PROVE-arith 契约批）——arith.mbt eval_int_binary /
/// eval_int_unary 的 I32 臂逐臂镜像（行号锚）。三态口径见批报告。
/// I32 分口径：Add/Sub/Mul/Neg 数学越域 ⇔ Err(*Overflow)（教学 trap 语义
/// 表镜像）；Div/Mod 全域除零 + INT_MIN/-1 拒绝；移位量 0..31 判界。

///|
/// OpAdd→I32 臂（arith.mbt:183-190）：溢出检查完备双向 + Ok 值域。
fn m_add_i32(
  l : Int64,
  r : Int64,
) -> Outcome where {
  proof_require: in_dom(l, I32),
  proof_require: in_dom(r, I32),
  proof_ensure: result => {
    match result {
      V(v) => -2147483648L <= v && v <= 2147483647L
      F(f) =>
        match f {
          FAddOverflow => l + r > 2147483647L || l + r < -2147483648L
          _ => false
        }
    }
  },
} {
  let v = l + r
  if v > 2147483647L || v < -2147483648L {
    F(FAddOverflow)
  } else {
    V(v)
  }
}

///|
/// OpSub→I32 臂（arith.mbt:196-203）：同 Add 形态。
fn m_sub_i32(
  l : Int64,
  r : Int64,
) -> Outcome where {
  proof_require: in_dom(l, I32),
  proof_require: in_dom(r, I32),
  proof_ensure: result => {
    match result {
      V(v) => -2147483648L <= v && v <= 2147483647L
      F(f) =>
        match f {
          FSubOverflow => l - r > 2147483647L || l - r < -2147483648L
          _ => false
        }
    }
  },
} {
  let v = l - r
  if v > 2147483647L || v < -2147483648L {
    F(FSubOverflow)
  } else {
    V(v)
  }
}

///|
/// OpMul→I32 臂（arith.mbt:209-216）：积域检查完备（无界语义下 l*r 数学积，
/// 检查直接可判——非线性不进证明面）。
fn m_mul_i32(
  l : Int64,
  r : Int64,
) -> Outcome where {
  proof_require: in_dom(l, I32),
  proof_require: in_dom(r, I32),
  proof_ensure: result => {
    match result {
      V(v) => -2147483648L <= v && v <= 2147483647L
      F(f) =>
        match f {
          FMulOverflow => l * r > 2147483647L || l * r < -2147483648L
          _ => false
        }
    }
  },
} {
  let v = l * r
  if v > 2147483647L || v < -2147483648L {
    F(FMulOverflow)
  } else {
    V(v)
  }
}

///|
/// OpDiv→I32 臂（arith.mbt:222-229）：除零/INT_MIN÷-1 拒绝完备 + 商值域
/// （|商| ≤ |l| 收缩 + 检查拦截防 2^31 越域格）。
fn m_div_i32(
  l : Int64,
  r : Int64,
) -> Outcome where {
  proof_require: in_dom(l, I32),
  proof_require: in_dom(r, I32),
  proof_ensure: result => {
    match result {
      V(v) =>
        r != 0L &&
        (l != -2147483648L || r != -1L) &&
        -2147483648L <= v &&
        v <= 2147483647L
      F(f) =>
        match f {
          FDivByZero => r == 0L
          FDivOverflow => l == -2147483648L && r == -1L
          _ => false
        }
    }
  },
} {
  if r == 0L {
    F(FDivByZero)
  } else if l == -2147483648L && r == -1L {
    F(FDivOverflow)
  } else {
    V(l / r)
  }
}

///|
/// OpMod→I32 臂（arith.mbt:251-258）：拒绝路径同 Div；余数 |余| < |r| ≤ max
/// 收缩（C 截断取余符号随被除数，|l%r| < |r| 界两侧同形）。
fn m_mod_i32(
  l : Int64,
  r : Int64,
) -> Outcome where {
  proof_require: in_dom(l, I32),
  proof_require: in_dom(r, I32),
  proof_ensure: result => {
    match result {
      V(v) =>
        r != 0L &&
        (l != -2147483648L || r != -1L) &&
        -2147483648L <= v &&
        v <= 2147483647L
      F(f) =>
        match f {
          FDivByZero => r == 0L
          FDivOverflow => l == -2147483648L && r == -1L
          _ => false
        }
    }
  },
} {
  if r == 0L {
    F(FDivByZero)
  } else if l == -2147483648L && r == -1L {
    F(FDivOverflow)
  } else {
    V(l % r)
  }
}

///|
/// OpShl→I32 臂（arith.mbt:281-285）：`normalize(l << s, I32)` 的算术化 =
/// wrap32s(l * 2^s)——值域完备由 wrap32s 像集引理直出（与操作数值无关）。
fn m_shl_i32(
  l : Int64,
  s : Int32,
) -> Outcome where {
  proof_require: in_dom(l, I32),
  proof_require: 0 <= s,
  proof_require: s < 32,
  proof_ensure: result => {
    match result {
      V(v) => -2147483648L <= v && v <= 2147483647L
      F(_) => false
    }
  },
} {
  V(wrap32s(l * two_pow(s)))
}

///|
/// OpShr→I32 臂（arith.mbt:286-297 I32|I64 算术右移）：`l >> s` 算术化 =
/// floor(l / 2^s)——值域收缩（结果夹在 l 与 0 之间 ⊆ I32 域）。
fn m_shr_i32(
  l : Int64,
  s : Int32,
) -> Outcome where {
  proof_require: in_dom(l, I32),
  proof_require: 0 <= s,
  proof_require: s < 32,
  proof_ensure: result => {
    match result {
      V(v) => -2147483648L <= v && v <= 2147483647L
      F(_) => false
    }
  },
} {
  V(floor_div_pos(l, two_pow(s)))
}

///|
/// OpNeg→I32 臂（arith.mbt OpNeg→I32，eval_int_unary）：INT_MIN 取反对
/// 拒绝完备 + 其余值域（-v ∈ 域 when v > min）。
fn m_neg_i32(
  v : Int64,
) -> Outcome where {
  proof_require: in_dom(v, I32),
  proof_ensure: result => {
    match result {
      V(x) => -2147483648L <= x && x <= 2147483647L && v != -2147483648L
      F(f) =>
        match f {
          FNegOverflow => v == -2147483648L
          _ => false
        }
    }
  },
} {
  if v == -2147483648L {
    F(FNegOverflow)
  } else {
    V(-v)
  }
}

///|
/// OpBitNot→I32 臂（arith.mbt OpBitNot，-1L - v 代数式）：~v = -v - 1 域
/// 封闭（min 时 -1-min = max 线性）。
fn m_bitnot_i32(
  v : Int64,
) -> Outcome where {
  proof_require: in_dom(v, I32),
  proof_ensure: result => {
    match result {
      V(x) => -2147483648L <= x && x <= 2147483647L
      F(_) => false
    }
  },
} {
  V(-1L - v)
}

///|
/// OpLt→I32 臂（arith.mbt:298，cmp_lt I32 直接 <）：比较结果 0/1 规范。
fn m_lt_i32(
  l : Int64,
  r : Int64,
) -> Outcome where {
  proof_require: in_dom(l, I32),
  proof_require: in_dom(r, I32),
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
/// OpLe→I32 臂（arith.mbt:299，Le = !(r < l) 反转形态）。
fn m_le_i32(
  l : Int64,
  r : Int64,
) -> Outcome where {
  proof_require: in_dom(l, I32),
  proof_require: in_dom(r, I32),
  proof_ensure: result => {
    match result {
      V(v) => v == 0L || v == 1L
      F(_) => false
    }
  },
} {
  V(if r < l { 0L } else { 1L })
}

///|
/// OpGt→I32 臂（arith.mbt:300）。
fn m_gt_i32(
  l : Int64,
  r : Int64,
) -> Outcome where {
  proof_require: in_dom(l, I32),
  proof_require: in_dom(r, I32),
  proof_ensure: result => {
    match result {
      V(v) => v == 0L || v == 1L
      F(_) => false
    }
  },
} {
  V(if r < l { 1L } else { 0L })
}

///|
/// OpGe→I32 臂（arith.mbt:301）。
fn m_ge_i32(
  l : Int64,
  r : Int64,
) -> Outcome where {
  proof_require: in_dom(l, I32),
  proof_require: in_dom(r, I32),
  proof_ensure: result => {
    match result {
      V(v) => v == 0L || v == 1L
      F(_) => false
    }
  },
} {
  V(if l < r { 0L } else { 1L })
}

///|
/// OpEq→I32 臂（arith.mbt:302，规范值位模式相等——A2 解）。
fn m_eq_i32(
  l : Int64,
  r : Int64,
) -> Outcome where {
  proof_require: in_dom(l, I32),
  proof_require: in_dom(r, I32),
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
/// OpNe→I32 臂（arith.mbt:303）。
fn m_ne_i32(
  l : Int64,
  r : Int64,
) -> Outcome where {
  proof_require: in_dom(l, I32),
  proof_require: in_dom(r, I32),
  proof_ensure: result => {
    match result {
      V(v) => v == 0L || v == 1L
      F(_) => false
    }
  },
} {
  V(if l != r { 1L } else { 0L })
}
