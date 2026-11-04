///|
/// 白盒逐臂矩阵对拍（PR #480 审阅 P2-3 处置批，2026-11-05）——镜像全部
/// 私有算子臂 × `@arith.eval_int_binary`/`eval_int_unary` 原件的**值级**
/// 对拍矩阵（边界值 + 0/±1/MIN/MAX/跨符号位）。
/// **wbtest 跨包实锤**（审阅 1762 组矩阵探针）：包级 import 在 `_wbtest.mbt`
/// 可直接以 `@arith.` 消费——本仓手册陷阱 26 的「wbtest 不携带 for-test
/// import」论断据此修正（该陷阱的历史语境是测试专用依赖形态，包级
/// import 不受限）。本文件即此前「镜像逐臂零运行期锚」缺口的补全：
/// prove 不进 CI 期间，镜像↔原件的逐臂组合语义由本矩阵机判。
/// U64 面（m_div_u64/m_mod_u64）V 路径为哨兵值（mirror_u64.mbt 头注
/// 登记）——只对拍拒绝路径；m_eq_u64/m_bitnot_u64 位模式语义全对拍。

///|
/// 故障镜像 ↔ 原件 ArithFault 等值判定（七故障逐一映射）
fn fault_eq(f : Fault, e : @arith.ArithFault) -> Bool {
  match (f, e) {
    (FDivByZero, @arith.DivByZero) => true
    (FDivOverflow, @arith.DivOverflow) => true
    (FShiftOutOfRange(a), @arith.ShiftOutOfRange(b)) => a == b
    (FAddOverflow, @arith.AddOverflow) => true
    (FSubOverflow, @arith.SubOverflow) => true
    (FMulOverflow, @arith.MulOverflow) => true
    (FNegOverflow, @arith.NegOverflow) => true
    _ => false
  }
}

///|
/// 二元算子对拍单格：镜像 Outcome ↔ 原件 Result 等值断言
fn chk_bin(
  m : (Int64, Int64) -> Outcome,
  op : @arith.IntBinOp,
  l : Int64,
  r : Int64,
  dom : @arith.IntDomain,
  tag : String,
) -> Unit raise {
  let orig = @arith.eval_int_binary(op, l, r, dom)
  let mir : Outcome = m(l, r)
  let ok : Bool = match (mir, orig) {
    (V(v), Ok(w)) => v == w
    (F(f), Err(e)) => fault_eq(f, e)
    _ => false
  }
  assert_true(ok, msg=tag)
}

///|
/// 一元算子对拍单格
fn chk_un(
  m : (Int64) -> Outcome,
  op : @arith.IntUnOp,
  v : Int64,
  dom : @arith.IntDomain,
  tag : String,
) -> Unit raise {
  let orig = @arith.eval_int_unary(op, v, dom)
  let mir : Outcome = m(v)
  let ok : Bool = match (mir, orig) {
    (V(a), Ok(w)) => a == w
    (F(f), Err(e)) => fault_eq(f, e)
    _ => false
  }
  assert_true(ok, msg=tag)
}

///|
/// 移位算子对拍单格（镜像 s : Int，原件移位量 Int64）
fn chk_shift(
  m : (Int64, Int32) -> Outcome,
  op : @arith.IntBinOp,
  l : Int64,
  s : Int32,
  dom : @arith.IntDomain,
  tag : String,
) -> Unit raise {
  let orig = @arith.eval_int_binary(op, l, s.to_int64(), dom)
  let mir : Outcome = m(l, s)
  let ok : Bool = match (mir, orig) {
    (V(v), Ok(w)) => v == w
    (F(f), Err(e)) => fault_eq(f, e)
    _ => false
  }
  assert_true(ok, msg=tag)
}

///|
test "wb_matrix_i32_binary" {
  let vals : Array[Int64] = [
    0L, 1L, -1L, 2L, -2L, 100L, -100L, 2147483647L, -2147483648L, 2147483646L, -2147483647L,
    12345L, -99999L,
  ]
  for l in vals {
    for r in vals {
      chk_bin(m_add_i32, @arith.OpAdd, l, r, @arith.I32, "Add I32 \{l} \{r}")
      chk_bin(m_sub_i32, @arith.OpSub, l, r, @arith.I32, "Sub I32 \{l} \{r}")
      chk_bin(m_mul_i32, @arith.OpMul, l, r, @arith.I32, "Mul I32 \{l} \{r}")
      chk_bin(m_div_i32, @arith.OpDiv, l, r, @arith.I32, "Div I32 \{l} \{r}")
      chk_bin(m_mod_i32, @arith.OpMod, l, r, @arith.I32, "Mod I32 \{l} \{r}")
      chk_bin(m_lt_i32, @arith.OpLt, l, r, @arith.I32, "Lt I32 \{l} \{r}")
      chk_bin(m_le_i32, @arith.OpLe, l, r, @arith.I32, "Le I32 \{l} \{r}")
      chk_bin(m_gt_i32, @arith.OpGt, l, r, @arith.I32, "Gt I32 \{l} \{r}")
      chk_bin(m_ge_i32, @arith.OpGe, l, r, @arith.I32, "Ge I32 \{l} \{r}")
      chk_bin(m_eq_i32, @arith.OpEq, l, r, @arith.I32, "Eq I32 \{l} \{r}")
      chk_bin(m_ne_i32, @arith.OpNe, l, r, @arith.I32, "Ne I32 \{l} \{r}")
    }
  }
}

///|
test "wb_matrix_i32_shift_unary" {
  let vals : Array[Int64] = [
    0L, 1L, -1L, 100L, -100L, 2147483647L, -2147483648L, 2147483646L, -2147483647L,
  ]
  let ss : Array[Int32] = [0, 1, 5, 30, 31]
  for l in vals {
    for s in ss {
      chk_shift(m_shl_i32, @arith.OpShl, l, s, @arith.I32, "Shl I32 \{l} \{s}")
      chk_shift(m_shr_i32, @arith.OpShr, l, s, @arith.I32, "Shr I32 \{l} \{s}")
    }
    chk_un(m_neg_i32, @arith.OpNeg, l, @arith.I32, "Neg I32 \{l}")
    chk_un(m_bitnot_i32, @arith.OpBitNot, l, @arith.I32, "BitNot I32 \{l}")
  }
}

///|
test "wb_matrix_u32_binary" {
  let vals : Array[Int64] = [
    0L, 1L, 4294967295L, 4294967294L, 2147483648L, 2147483647L, 100L, 65535L,
  ]
  for l in vals {
    for r in vals {
      chk_bin(m_add_u32, @arith.OpAdd, l, r, @arith.U32, "Add U32 \{l} \{r}")
      chk_bin(m_sub_u32, @arith.OpSub, l, r, @arith.U32, "Sub U32 \{l} \{r}")
      chk_bin(m_mul_u32, @arith.OpMul, l, r, @arith.U32, "Mul U32 \{l} \{r}")
      chk_bin(m_div_u32, @arith.OpDiv, l, r, @arith.U32, "Div U32 \{l} \{r}")
      chk_bin(m_mod_u32, @arith.OpMod, l, r, @arith.U32, "Mod U32 \{l} \{r}")
      chk_bin(m_lt_u32, @arith.OpLt, l, r, @arith.U32, "Lt U32 \{l} \{r}")
      chk_bin(m_le_u32, @arith.OpLe, l, r, @arith.U32, "Le U32 \{l} \{r}")
      chk_bin(m_gt_u32, @arith.OpGt, l, r, @arith.U32, "Gt U32 \{l} \{r}")
      chk_bin(m_ge_u32, @arith.OpGe, l, r, @arith.U32, "Ge U32 \{l} \{r}")
      chk_bin(m_eq_u32, @arith.OpEq, l, r, @arith.U32, "Eq U32 \{l} \{r}")
      chk_bin(m_ne_u32, @arith.OpNe, l, r, @arith.U32, "Ne U32 \{l} \{r}")
    }
  }
}

///|
test "wb_matrix_u32_shift_unary" {
  let vals : Array[Int64] = [
    0L, 1L, 4294967295L, 2147483648L, 2147483647L, 100L,
  ]
  let ss : Array[Int32] = [0, 1, 5, 30, 31]
  for l in vals {
    for s in ss {
      chk_shift(m_shl_u32, @arith.OpShl, l, s, @arith.U32, "Shl U32 \{l} \{s}")
      chk_shift(m_shr_u32, @arith.OpShr, l, s, @arith.U32, "Shr U32 \{l} \{s}")
    }
    chk_un(m_neg_u32, @arith.OpNeg, l, @arith.U32, "Neg U32 \{l}")
    chk_un(m_bitnot_u32, @arith.OpBitNot, l, @arith.U32, "BitNot U32 \{l}")
  }
}

///|
test "wb_matrix_i64_proof_face" {
  let vals : Array[Int64] = [
    0L, 1L, -1L, 100L, -100L, 9223372036854775807L, -9223372036854775808L, 4294967296L,
    -4294967296L, -2147483648L, 2147483647L,
  ]
  for l in vals {
    for r in vals {
      chk_bin(m_div_i64, @arith.OpDiv, l, r, @arith.I64, "Div I64 \{l} \{r}")
      chk_bin(m_mod_i64, @arith.OpMod, l, r, @arith.I64, "Mod I64 \{l} \{r}")
      chk_bin(m_lt_i64, @arith.OpLt, l, r, @arith.I64, "Lt I64 \{l} \{r}")
      chk_bin(m_eq_i64, @arith.OpEq, l, r, @arith.I64, "Eq I64 \{l} \{r}")
    }
    chk_un(m_neg_i64, @arith.OpNeg, l, @arith.I64, "Neg I64 \{l}")
    chk_un(m_bitnot_i64, @arith.OpBitNot, l, @arith.I64, "BitNot I64 \{l}")
  }
  // 移位含 s=63 全量右移特判格（PR #480 审阅 P3-5 修复锚——修复前该格
  // 与原件分叉，本矩阵此格即当时唯一红点）
  let svals : Array[Int64] = [
    0L, 1L, -1L, 100L, -100L, 9223372036854775807L, -9223372036854775808L, 4294967296L,
    -4294967296L,
  ]
  let ss : Array[Int32] = [0, 1, 6, 31, 32, 62, 63]
  for l in svals {
    for s in ss {
      chk_shift(m_shr_i64, @arith.OpShr, l, s, @arith.I64, "Shr I64 \{l} \{s}")
    }
  }
}

///|
test "wb_matrix_u64_proof_face" {
  let vals : Array[Int64] = [
    0L, 1L, -1L, 100L, -100L, 9223372036854775807L, -9223372036854775808L, 4294967295L,
    -4294967296L,
  ]
  // Div/Mod：只对拍拒绝路径（V 哨兵登记，见文件头注）
  for l in vals {
    for r in vals {
      let orig_div = @arith.eval_int_binary(@arith.OpDiv, l, r, @arith.U64)
      let mir_div : Outcome = m_div_u64(l, r)
      let orig_mod = @arith.eval_int_binary(@arith.OpMod, l, r, @arith.U64)
      let mir_mod : Outcome = m_mod_u64(l, r)
      if r == 0L {
        let okd = match (mir_div, orig_div) {
          (F(FDivByZero), Err(@arith.DivByZero)) => true
          _ => false
        }
        let okm = match (mir_mod, orig_mod) {
          (F(FDivByZero), Err(@arith.DivByZero)) => true
          _ => false
        }
        assert_true(okd, msg="Div U64 拒绝 \{l} 0")
        assert_true(okm, msg="Mod U64 拒绝 \{l} 0")
      } else {
        let okd = match (mir_div, orig_div) {
          (V(_), Ok(_)) => true
          _ => false
        }
        let okm = match (mir_mod, orig_mod) {
          (V(_), Ok(_)) => true
          _ => false
        }
        assert_true(okd, msg="Div U64 非拒绝 \{l} \{r}")
        assert_true(okm, msg="Mod U64 非拒绝 \{l} \{r}")
      }
    }
  }
  // Eq/BitNot：位模式语义全对拍
  for l in vals {
    for r in vals {
      chk_bin(m_eq_u64, @arith.OpEq, l, r, @arith.U64, "Eq U64 \{l} \{r}")
    }
    chk_un(m_bitnot_u64, @arith.OpBitNot, l, @arith.U64, "BitNot U64 \{l}")
  }
}
