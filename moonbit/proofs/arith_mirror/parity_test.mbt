///|
/// 黑盒对拍锚（PROVE-arith 批）——镜像证明包与 vitro/engine/arith 原函数
/// 的信任桥。三层：①wrap 模型 ↔ normalize 函数级等价（回绕族核心锚）
/// ②two_pow 幂表常量锚 ③原函数拒绝路径行为锚（证明所断言拒绝完备性的
/// 采样对照）。
/// ~~wbtest 不携带 for-test import（无法跨包）~~——**该论断有误**（PR #480
/// 审阅 1762 组矩阵实锤：包级 import 在 _wbtest.mbt 可直接 @arith. 消费；
/// 陷阱 26 历史语境是测试专用依赖形态）。逐臂值对拍已由 mirror_wbtest.mbt
/// 白盒矩阵承接（2026-11-05 处置批）；本文件保留黑盒面（pub 引理可达性
/// 的同形锚）。

///|
/// wrap 模型 ↔ normalize 函数级等价（采样含全部边界形态：正负、跨 2^31
/// /2^32 档、Int64 极值）
test "parity_wrap_model_vs_normalize" {
  let samples = [
    0L, 1L, -1L, 12345L, -99999L, 2147483647L, 2147483648L, -2147483648L, -2147483649L,
    4294967295L, 4294967296L, 4294967297L, 9223372036854775807L, -9223372036854775808L,
  ]
  for v in samples {
    assert_eq(
      @arith_mirror.wrap32u(v),
      @arith.normalize(v, @arith.U32),
      msg="wrap32u(\{v}) 应与 normalize U32 逐位一致",
    )
    assert_eq(
      @arith_mirror.wrap32s(v),
      @arith.normalize(v, @arith.I32),
      msg="wrap32s(\{v}) 应与 normalize I32 逐位一致",
    )
  }
}

///|
/// two_pow 幂表常量锚（s ≤ 62 域内可执行；63 越域格登记排除——运行时
/// 回绕，证明层无界语义正确覆盖）
test "parity_two_pow_constants" {
  assert_eq(@arith_mirror.two_pow(0), 1L, msg="2^0")
  assert_eq(@arith_mirror.two_pow(1), 2L, msg="2^1")
  assert_eq(@arith_mirror.two_pow(10), 1024L, msg="2^10")
  assert_eq(@arith_mirror.two_pow(31), 2147483648L, msg="2^31")
  assert_eq(@arith_mirror.two_pow(32), 4294967296L, msg="2^32")
  assert_eq(@arith_mirror.two_pow(62), 4611686018427387904L, msg="2^62")
}

///|
/// 拒绝路径行为锚——证明所断言「拒绝 ⇔ 完备」的采样对照（原函数侧真值）
test "parity_reject_paths" {
  // DivByZero 四域全格
  assert_eq(
    @arith.eval_int_binary(@arith.OpDiv, 1L, 0L, @arith.I32),
    Err(@arith.DivByZero),
    msg="Div I32 除零",
  )
  assert_eq(
    @arith.eval_int_binary(@arith.OpDiv, 1L, 0L, @arith.U32),
    Err(@arith.DivByZero),
    msg="Div U32 除零",
  )
  assert_eq(
    @arith.eval_int_binary(@arith.OpDiv, 1L, 0L, @arith.I64),
    Err(@arith.DivByZero),
    msg="Div I64 除零",
  )
  assert_eq(
    @arith.eval_int_binary(@arith.OpDiv, 1L, 0L, @arith.U64),
    Err(@arith.DivByZero),
    msg="Div U64 除零（位模式零）",
  )
  assert_eq(
    @arith.eval_int_binary(@arith.OpMod, 7L, 0L, @arith.I64),
    Err(@arith.DivByZero),
    msg="Mod I64 除零",
  )
  // DivOverflow：INT_MIN/-1 与 LLONG_MIN/-1（U 域无此面）
  assert_eq(
    @arith.eval_int_binary(@arith.OpDiv, -2147483648L, -1L, @arith.I32),
    Err(@arith.DivOverflow),
    msg="Div I32 INT_MIN/-1",
  )
  assert_eq(
    @arith.eval_int_binary(@arith.OpDiv, -9223372036854775808L, -1L, @arith.I64),
    Err(@arith.DivOverflow),
    msg="Div I64 LLONG_MIN/-1",
  )
  // ShiftOutOfRange：负移位量与越上界（32/64 域宽），原值随故障带回
  assert_eq(
    @arith.eval_int_binary(@arith.OpShl, 1L, -1L, @arith.I32),
    Err(@arith.ShiftOutOfRange(-1L)),
    msg="Shl I32 负移位量",
  )
  assert_eq(
    @arith.eval_int_binary(@arith.OpShl, 1L, 32L, @arith.I32),
    Err(@arith.ShiftOutOfRange(32L)),
    msg="Shl I32 越上界 32",
  )
  assert_eq(
    @arith.eval_int_binary(@arith.OpShr, 1L, 64L, @arith.I64),
    Err(@arith.ShiftOutOfRange(64L)),
    msg="Shr I64 越上界 64",
  )
  assert_eq(
    @arith.eval_int_binary(@arith.OpShr, 1L, 63L, @arith.U64),
    Ok(0L),
    msg="Shr U64 63 在界（边界内不拒）",
  )
  // I32 溢出族（教学 trap 口径——U32/I64/U64 同格回绕不拒，分口径锚）
  assert_eq(
    @arith.eval_int_binary(@arith.OpAdd, 2147483647L, 1L, @arith.I32),
    Err(@arith.AddOverflow),
    msg="Add I32 max+1 溢出",
  )
  assert_eq(
    @arith.eval_int_binary(@arith.OpSub, -2147483648L, 1L, @arith.I32),
    Err(@arith.SubOverflow),
    msg="Sub I32 min-1 溢出",
  )
  assert_eq(
    @arith.eval_int_binary(@arith.OpMul, 65536L, 65536L, @arith.I32),
    Err(@arith.MulOverflow),
    msg="Mul I32 2^16*2^16 溢出",
  )
  assert_eq(
    @arith.eval_int_unary(@arith.OpNeg, -2147483648L, @arith.I32),
    Err(@arith.NegOverflow),
    msg="Neg I32 INT_MIN 溢出",
  )
  assert_eq(
    @arith.eval_int_binary(@arith.OpAdd, 2147483647L, 1L, @arith.U32),
    Ok(2147483648L),
    msg="Add U32 同格回绕不拒（分口径）",
  )
  assert_eq(
    @arith.eval_int_unary(@arith.OpNeg, -9223372036854775808L, @arith.I64),
    Err(@arith.NegOverflow),
    msg="Neg I64 LLONG_MIN 溢出",
  )
}

///|
/// 移位量判界镜像 ↔ 原函数行为锚（m_shift_guard 的 GOk/GBad 采样对照）
test "parity_shift_guard" {
  assert_eq(
    @arith_mirror.m_shift_guard(32L, 0L),
    GOk,
    msg="I32 档移位 0 在界",
  )
  assert_eq(
    @arith_mirror.m_shift_guard(32L, 31L),
    GOk,
    msg="I32 档移位 31 在界（上界含）",
  )
  assert_eq(
    @arith_mirror.m_shift_guard(32L, 32L),
    GBad(32L),
    msg="I32 档移位 32 越上界（原值带回）",
  )
  assert_eq(
    @arith_mirror.m_shift_guard(64L, 63L),
    GOk,
    msg="I64 档移位 63 在界",
  )
  assert_eq(
    @arith_mirror.m_shift_guard(64L, -1L),
    GBad(-1L),
    msg="负移位量拒",
  )
}

///|
/// 原函数 Ok 值域采样锚——证明所断言「Ok 值 ∈ 域」的行为对照（挑可回绕
/// 域的越档格：U32 大值乘积回绕后仍在 [0, 2^32)）
test "parity_ok_value_domain_samples" {
  let r = @arith.eval_int_binary(
    @arith.OpMul,
    4294967295L,
    4294967295L,
    @arith.U32,
  )
  assert_true(
    match r {
      Ok(v) => v >= 0L && v <= 4294967295L
      Err(_) => false
    },
    msg="U32 (2^32-1)^2 回绕值仍在 U32 域",
  )
  let r2 = @arith.eval_int_binary(@arith.OpAdd, -1L, -1L, @arith.U32)
  assert_true(
    match r2 {
      Ok(v) => v >= 0L && v <= 4294967295L
      Err(_) => false
    },
    msg="U32 (-1)+(-1) 位模式回绕值仍在 U32 域",
  )
  let r3 = @arith.eval_int_binary(@arith.OpShl, 2147483647L, 31L, @arith.I32)
  assert_true(
    match r3 {
      Ok(v) => v >= -2147483648L && v <= 2147483647L
      Err(_) => false
    },
    msg="I32 max<<31 截 32 位后仍在 I32 域",
  )
}
