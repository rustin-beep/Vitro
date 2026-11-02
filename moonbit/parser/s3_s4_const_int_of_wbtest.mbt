///|
/// #426 B3' 批 4 防御锚（扫描 S3/S4）：parser 第二套求值器 `const_int_of`
/// （数组维度，Int32 无类型）两处运算性缺口——
/// S3：Div/Mod 无 INT_MIN/-1 检查（MoonBit Int32 除法在 wasm 后端 trap、
///     JS 后端回绕——同一引擎按后端行为分叉的潜在 arm_divergence 面）；
/// S4：Shl/Shr 无移位量检查（MoonBit Int 移位按低 5 位掩码：`1<<32` 算成
///     `1<<0`=1 → `int arr[1<<32]` **静默折出定长 1**，而非 VLA 回退；
///     与 typeck 折叠（越界拒折）、VM（trap）三方各异）。
/// 拍板②：只加防御（命中 → None → VLA 诚实形态），不接核（E2 无类型信息，
/// 教学域数组维度几乎全 int；假 I32 域接核收益小）。J9 先红后修。
test "s3_s4_const_int_of_defends_div_overflow_and_shift_range" {
  let loc = @source.SourceLoc::new(1, 1)
  fn lit(v : Int32) -> @ast.Expr {
    @ast.Expr::Literal(v, loc, @ast.Type::int())
  }
  fn bin(op : @ast.BinaryOp, l : @ast.Expr, r : @ast.Expr) -> @ast.Expr {
    @ast.Expr::Binary(op, l, r, loc, @ast.Type::int())
  }
  // S4：移位量越界 → None（旧 1<<32 按掩码得 Some(1)）
  assert_eq(
    const_int_of(bin(Shl, lit(1), lit(32))),
    None,
    msg="1<<32 维度应拒折回退 VLA（旧静默折 1）",
  )
  assert_eq(
    const_int_of(bin(Shl, lit(1), lit(-1))),
    None,
    msg="负移位量应拒折",
  )
  assert_eq(
    const_int_of(bin(Shr, lit(1), lit(32))),
    None,
    msg="右移越界同拒",
  )
  // S3：INT_MIN / -1、INT_MIN % -1 → None（旧 js 回绕 / wasm trap）
  assert_eq(
    const_int_of(bin(Div, lit(-2147483648), lit(-1))),
    None,
    msg="INT_MIN/-1 维度应拒折（旧按后端回绕或 trap）",
  )
  assert_eq(
    const_int_of(bin(Mod, lit(-2147483648), lit(-1))),
    None,
    msg="INT_MIN%-1 维度应拒折",
  )
  // 正对照：域内值照旧可折
  assert_eq(const_int_of(bin(Shl, lit(1), lit(4))), Some(16))
  assert_eq(const_int_of(bin(Shr, lit(16), lit(2))), Some(4))
  assert_eq(const_int_of(bin(Div, lit(7), lit(-1))), Some(-7))
  assert_eq(
    const_int_of(bin(Div, lit(7), lit(0))),
    None,
    msg="除零既有拒折不变",
  )
}
