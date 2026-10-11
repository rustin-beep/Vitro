///|
/// 病 40 锚（#71 第二梯队，2026-10-11）：const_int_of 深链求值——
/// 2 万层右嵌套二元 + 一元链，递归版在 wasm 测试运行时栈溢出（对齐
/// `eval_enum_const` 迭代化先例；AST 构造本身循环无递归）。
test "const_int_of_deep_chain_issue71_b40" {
  let loc = @source.SourceLoc::new(1, 1)
  // 1+(1+(1+...+1))——20000 层右嵌套
  let mut e : @ast.Expr = @ast.Expr::Literal(1, loc, @ast.Type::int())
  for _i in 0..<20000 {
    e = @ast.Expr::Binary(
      Add,
      @ast.Expr::Literal(1, loc, @ast.Type::int()),
      e,
      loc,
      @ast.Type::int(),
    )
  }
  assert_eq(const_int_of(e), Some(20001))
  // ~(~(...~5))——20000 层一元位非链
  let mut u : @ast.Expr = @ast.Expr::Literal(5, loc, @ast.Type::int())
  for _i in 0..<20000 {
    u = @ast.Expr::Unary(@ast.UnaryOp::BitNot, u, loc, @ast.Type::int())
  }
  assert_eq(const_int_of(u), Some(5))
}
