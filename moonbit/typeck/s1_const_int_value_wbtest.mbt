///|
/// #426 B3' 批 4 红锚（扫描 S1）：typeck 第三套求值器 `const_int_value`
/// 的 `Not` 臂按 `~v = -v-1` 求值——注释写「~（按位取反）」匹配的却是逻辑非
/// `Not`，而 `BitNot` 落 `else None`。端到端实锤：`int a[3]; int x = a[!0];`
/// 触发 W3051「数组下标为负数 -1」假警（clang -Wall 零警告，运行值 20 对；
/// js/native 双臂一致）。J9 先红后修。
test "s1_const_int_value_not_is_logical_not_bitwise" {
  let loc = @source.SourceLoc::new(1, 1)
  fn lit(v : Int32) -> @ast.Expr {
    @ast.Expr::Literal(v, loc, @ast.Type::int())
  }
  fn un(op : @ast.UnaryOp, e : @ast.Expr) -> @ast.Expr {
    @ast.Expr::Unary(op, e, loc, @ast.Type::int())
  }
  // 逻辑非：!0 → 1、!5 → 0（旧按 ~ 算出 -1 / -6）
  assert_eq(
    const_int_value(un(@ast.UnaryOp::Not, lit(0))),
    Some(1),
    msg="!0 应为 1（旧 -1——a[!0] 假警根因）",
  )
  assert_eq(
    const_int_value(un(@ast.UnaryOp::Not, lit(5))),
    Some(0),
    msg="!5 应为 0（旧 -6）",
  )
  // 位非：~0 → -1、~5 → -6（旧落 None——is_int_constant_expr 放行但求值面缺臂）
  assert_eq(
    const_int_value(un(@ast.UnaryOp::BitNot, lit(0))),
    Some(-1),
    msg="~0 应为 -1（旧 None）",
  )
  assert_eq(
    const_int_value(un(@ast.UnaryOp::BitNot, lit(5))),
    Some(-6),
    msg="~5 应为 -6",
  )
  // 既有三形不变：Literal / Neg / Pos
  assert_eq(const_int_value(lit(7)), Some(7))
  assert_eq(const_int_value(un(@ast.UnaryOp::Neg, lit(7))), Some(-7))
  assert_eq(const_int_value(un(@ast.UnaryOp::Pos, lit(7))), Some(7))
}
