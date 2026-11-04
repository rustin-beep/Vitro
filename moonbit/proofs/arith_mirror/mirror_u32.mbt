///|
/// U32 域全算子镜像（PROVE-arith 契约批）——arith.mbt eval_int_binary /
/// eval_int_unary 的 U32 臂逐臂镜像。U32 分口径：四则/取反/按位非模 2^32
/// 回绕（wrap32u 像集引理）；Div/Mod 除零拒绝（无 MIN/-1 面——无符号域
/// 不存在该溢出）；移位量 0..31 判界。BitAnd/BitOr/BitXor 域封闭登记
/// 未覆盖（单行位运算 body 无域分支笔误面，位分解模型成本见批报告）。

///|
/// OpAdd→U32 臂（arith.mbt:191）：模 2^32 回绕域完备，永不故障。
fn m_add_u32(
  l : Int64,
  r : Int64,
) -> Outcome where {
  proof_require: in_dom(l, U32),
  proof_require: in_dom(r, U32),
  proof_ensure: result => {
    match result {
      V(v) => 0L <= v && v <= 4294967295L
      F(_) => false
    }
  },
} {
  V(wrap32u(l + r))
}

///|
/// OpSub→U32 臂（arith.mbt:204）。
fn m_sub_u32(
  l : Int64,
  r : Int64,
) -> Outcome where {
  proof_require: in_dom(l, U32),
  proof_require: in_dom(r, U32),
  proof_ensure: result => {
    match result {
      V(v) => 0L <= v && v <= 4294967295L
      F(_) => false
    }
  },
} {
  V(wrap32u(l - r))
}

///|
/// OpMul→U32 臂（arith.mbt:217）。
fn m_mul_u32(
  l : Int64,
  r : Int64,
) -> Outcome where {
  proof_require: in_dom(l, U32),
  proof_require: in_dom(r, U32),
  proof_ensure: result => {
    match result {
      V(v) => 0L <= v && v <= 4294967295L
      F(_) => false
    }
  },
} {
  V(wrap32u(l * r))
}

///|
/// OpDiv→U32 臂（arith.mbt:230）：除零 ⇔ 拒绝；商域 [0, l] 收缩
/// （l/r ≥ 0 截断=floor，商 ≤ l）。
fn m_div_u32(
  l : Int64,
  r : Int64,
) -> Outcome where {
  proof_require: in_dom(l, U32),
  proof_require: in_dom(r, U32),
  proof_ensure: result => {
    match result {
      V(v) => r != 0L && 0L <= v && v <= l
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
    V(l / r)
  }
}

///|
/// OpMod→U32 臂（arith.mbt:259）：余数 [0, r) 收缩。
fn m_mod_u32(
  l : Int64,
  r : Int64,
) -> Outcome where {
  proof_require: in_dom(l, U32),
  proof_require: in_dom(r, U32),
  proof_ensure: result => {
    match result {
      V(v) => r != 0L && 0L <= v && v < r
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
    V(l % r)
  }
}

///|
/// OpShl→U32 臂（arith.mbt:281-285 normalize(l << s, U32)）：wrap32u 像集。
fn m_shl_u32(
  l : Int64,
  s : Int32,
) -> Outcome where {
  proof_require: in_dom(l, U32),
  proof_require: 0 <= s,
  proof_require: s < 32,
  proof_ensure: result => {
    match result {
      V(v) => 0L <= v && v <= 4294967295L
      F(_) => false
    }
  },
} {
  V(wrap32u(l * two_pow(s)))
}

///|
/// OpShr→U32 臂（arith.mbt:294 逻辑右移）：U32 规范值恒正，Int64 >> 即
/// 逻辑——算术化 l / 2^s 截断（正被除数截断=floor 同式），值域 [0, l]。
fn m_shr_u32(
  l : Int64,
  s : Int32,
) -> Outcome where {
  proof_require: in_dom(l, U32),
  proof_require: 0 <= s,
  proof_require: s < 32,
  proof_ensure: result => {
    match result {
      V(v) => 0L <= v && v <= l
      F(_) => false
    }
  },
} {
  V(l / two_pow(s))
}

///|
/// OpNeg→U32 臂（arith.mbt OpNeg→U32，normalize(0-v)）：模 2^32 补。
fn m_neg_u32(
  v : Int64,
) -> Outcome where {
  proof_require: in_dom(v, U32),
  proof_ensure: result => {
    match result {
      V(x) => 0L <= x && x <= 4294967295L
      F(_) => false
    }
  },
} {
  V(wrap32u(0L - v))
}

///|
/// OpBitNot→U32 臂（arith.mbt OpBitNot→U32，normalize(-1-v)）。
fn m_bitnot_u32(
  v : Int64,
) -> Outcome where {
  proof_require: in_dom(v, U32),
  proof_ensure: result => {
    match result {
      V(x) => 0L <= x && x <= 4294967295L
      F(_) => false
    }
  },
} {
  V(wrap32u(-1L - v))
}

///|
/// OpLt→U32 臂（arith.mbt:298，cmp_lt U32 规范值恒正直接 <）。
fn m_lt_u32(
  l : Int64,
  r : Int64,
) -> Outcome where {
  proof_require: in_dom(l, U32),
  proof_require: in_dom(r, U32),
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
/// OpLe→U32 臂（arith.mbt:299）。
fn m_le_u32(
  l : Int64,
  r : Int64,
) -> Outcome where {
  proof_require: in_dom(l, U32),
  proof_require: in_dom(r, U32),
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
/// OpGt→U32 臂（arith.mbt:300）。
fn m_gt_u32(
  l : Int64,
  r : Int64,
) -> Outcome where {
  proof_require: in_dom(l, U32),
  proof_require: in_dom(r, U32),
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
/// OpGe→U32 臂（arith.mbt:301）。
fn m_ge_u32(
  l : Int64,
  r : Int64,
) -> Outcome where {
  proof_require: in_dom(l, U32),
  proof_require: in_dom(r, U32),
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
/// OpEq→U32 臂（arith.mbt:302）。
fn m_eq_u32(
  l : Int64,
  r : Int64,
) -> Outcome where {
  proof_require: in_dom(l, U32),
  proof_require: in_dom(r, U32),
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
/// OpNe→U32 臂（arith.mbt:303）。
fn m_ne_u32(
  l : Int64,
  r : Int64,
) -> Outcome where {
  proof_require: in_dom(l, U32),
  proof_require: in_dom(r, U32),
  proof_ensure: result => {
    match result {
      V(v) => v == 0L || v == 1L
      F(_) => false
    }
  },
} {
  V(if l != r { 1L } else { 0L })
}
