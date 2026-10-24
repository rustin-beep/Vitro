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

///|
/// issue #285 红锚（2026-10-24）：声明符螺旋 const 层级。`char *const *p`
/// 按 C 右左法则 = pointer to (const pointer to char)——p 自身层（源码
/// 末位 `*`，紧邻标识符）**非** const，pointee 层（源码首位 `* const`）
/// const。旧前缀组装（源码序 wrap，链头=末位 `*`）与 interpret「自顶向
/// 下」（链头先变形 base、深层后 wrap 成外层）方向相反 ⇒ 纯多前缀形态
/// 层级贡献者互换：const 落最外层（`char** const`），精确匹配传参误报
/// W3053（G2/F 探针实锤）；对称形态（`char **`）贡献者互换无观察差异，
/// 数组后缀链头=最内维与 interpret 自洽故维度一直正确。
fn tok285(
  ty : @token.TokenType,
  text : String,
  line : Int32,
  col : Int32,
) -> @token.Token {
  {
    ty,
    text,
    loc: { line, column: col, file_id: 0, },
    byte_off: -1,
    real_line: -1,
  }
}

///|
test "wb declarator spiral const level issue285" {
  // `* const * p`
  let toks = [
    tok285(Star, "*", 1, 6),
    tok285(Const, "const", 1, 8),
    tok285(Star, "*", 1, 14),
    tok285(Identifier, "p", 1, 16),
    tok285(Eof, "", 1, 17),
  ]
  let q = Parser::with_mode(toks, false)
  let (ty, name) = q.parse_declarator(@ast.Type::int(), 0)
  inspect(name, content="p")
  guard ty is Pointer(outer_pointee, outer_const) else {
    fail("期望双层指针类型")
  }
  inspect(outer_const, content="false")
  guard outer_pointee is Pointer(_, inner_const) else {
    fail("期望 pointee 为指针（双层）")
  }
  inspect(inner_const, content="true")
}

///|
/// 对照格：`char ** const p`（const 挂 p 自身层——源码末位 `* const`）
/// 与 `char *const p`（单层自身 const）——修复后两形态层级不变式。
test "wb declarator spiral const level outer_and_single_forms" {
  // `* * const p`：p 自身层 const、pointee 层非 const
  let toks2 = [
    tok285(Star, "*", 1, 6),
    tok285(Star, "*", 1, 8),
    tok285(Const, "const", 1, 10),
    tok285(Identifier, "p", 1, 16),
    tok285(Eof, "", 1, 17),
  ]
  let q2 = Parser::with_mode(toks2, false)
  let (ty2, _) = q2.parse_declarator(@ast.Type::int(), 0)
  guard ty2 is Pointer(p2_pointee, p2_const) else { fail("期望指针") }
  inspect(p2_const, content="true")
  guard p2_pointee is Pointer(_, ic2) else { fail("期望双层") }
  inspect(ic2, content="false")
  // `* const p`：单层自身 const（既有正确行为回归格）
  let toks3 = [
    tok285(Star, "*", 1, 6),
    tok285(Const, "const", 1, 8),
    tok285(Identifier, "p", 1, 14),
    tok285(Eof, "", 1, 15),
  ]
  let q3 = Parser::with_mode(toks3, false)
  let (ty3, _) = q3.parse_declarator(@ast.Type::int(), 0)
  guard ty3 is Pointer(_, c3) else { fail("期望指针") }
  inspect(c3, content="true")
}
