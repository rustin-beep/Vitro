///|
/// round 负平局位锚（五轮审阅 P1：core 是 half-up，C99/oracle 是远离零）。
test "round_negative_ties_away_from_zero" {
  // -0.5 → -1.0（位 0xBFF0000000000000）；修复前 core 给 -0.0
  assert_eq(
    host_round((-0.5).reinterpret_as_uint64()),
    (-1.0).reinterpret_as_uint64(),
  )
  assert_eq(
    host_round((-1.5).reinterpret_as_uint64()),
    (-2.0).reinterpret_as_uint64(),
  )
  assert_eq(
    host_round((-2.5).reinterpret_as_uint64()),
    (-3.0).reinterpret_as_uint64(),
  )
  assert_eq(
    host_round((-3.5).reinterpret_as_uint64()),
    (-4.0).reinterpret_as_uint64(),
  )
  // 正平局与常规值回归（修复前后都应成立）
  assert_eq(
    host_round(2.5.reinterpret_as_uint64()),
    3.0.reinterpret_as_uint64(),
  )
  assert_eq(
    host_round((-0.4).reinterpret_as_uint64()),
    (-0.0).reinterpret_as_uint64(),
    msg="round(-0.4) = -0.0（负零符号保留——ceil 直返）",
  )
  // ±0 / NaN / 大整数域直返
  assert_eq(host_round(0UL), 0UL)
  assert_eq(
    host_round((-0.0).reinterpret_as_uint64()),
    (-0.0).reinterpret_as_uint64(),
  )
}

// ── Host Contract 三态对账补锚段（2026-10-04，总计划表 3 收官清零）──
// math 基本值族 10 条：oracle host_contract_tests.rs:580-672 断言照搬
//（EPS=1e-9；位模式直调形态——mb 侧 host_* 免 vm 装配）。

///|
test "math_sin_zero" {
  let r = host_sin(0.0.reinterpret_as_uint64())
  assert_true(
    r.reinterpret_as_double().abs() < 0.000000001,
    msg="sin(0.0) 应接近 0",
  )
}

///|
test "math_cos_zero" {
  let r = host_cos(0.0.reinterpret_as_uint64())
  assert_true(
    (r.reinterpret_as_double() - 1.0).abs() < 0.000000001,
    msg="cos(0.0) 应接近 1",
  )
}

///|
test "math_sqrt_four" {
  let r = host_sqrt(4.0.reinterpret_as_uint64())
  assert_true(
    (r.reinterpret_as_double() - 2.0).abs() < 0.000000001,
    msg="sqrt(4.0) 应接近 2",
  )
}

///|
test "math_pow_two_three" {
  // oracle 调用约定：y 先压后 x（pop 序 x 在顶）——直调形态 (x, y)
  let r = host_pow(2.0.reinterpret_as_uint64(), 3.0.reinterpret_as_uint64())
  assert_true(
    (r.reinterpret_as_double() - 8.0).abs() < 0.000000001,
    msg="pow(2.0, 3.0) 应接近 8",
  )
}

///|
test "math_atan_zero" {
  let r = host_atan(0.0.reinterpret_as_uint64())
  assert_true(
    r.reinterpret_as_double().abs() < 0.000000001,
    msg="atan(0.0) 应接近 0",
  )
}

///|
test "math_log_one" {
  let r = host_log(1.0.reinterpret_as_uint64())
  assert_true(
    r.reinterpret_as_double().abs() < 0.000000001,
    msg="log(1.0) 应接近 0",
  )
}

///|
test "math_exp_zero" {
  let r = host_exp(0.0.reinterpret_as_uint64())
  assert_true(
    (r.reinterpret_as_double() - 1.0).abs() < 0.000000001,
    msg="exp(0.0) 应接近 1",
  )
}

///|
test "math_sin_half_pi" {
  let half_pi = 1.5707963267948966
  let r = host_sin(half_pi.reinterpret_as_uint64())
  assert_true(
    (r.reinterpret_as_double() - 1.0).abs() < 0.000000001,
    msg="sin(pi/2) 应接近 1",
  )
}

///|
test "math_sqrt_negative_returns_nan" {
  let r = host_sqrt((-1.0).reinterpret_as_uint64())
  assert_true(r.reinterpret_as_double().is_nan(), msg="sqrt(-1.0) 应 NaN")
}

///|
test "math_log_zero_returns_neg_inf" {
  let r = host_log(0.0.reinterpret_as_uint64())
  // -inf 位模式 0xFFF0000000000000（core 无 is_infinite——位判定）
  assert_eq(r, 0xFFF0000000000000UL, msg="log(0.0) 应 -inf")
}
