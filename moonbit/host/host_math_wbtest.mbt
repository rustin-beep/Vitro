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
