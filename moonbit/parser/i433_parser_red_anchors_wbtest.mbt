///|
/// #433 批 B9 三批 parser 侧红锚（2026-11-12，M04 连坐放行——用户拍板
/// 「形态完整性优先于文件面」，根因在 parser/expr.mbt）：M04-A1 三元
/// then 拒逗号（C11 §6.5.15 then 是完整 expression）+ M04-A2 L 后缀
/// 字面量定型与 long 同宽（§6.4.4.1 定 1L 类型为 long——vitro 钉 LLP64
/// long=4B；修前一律 long_long 令 sizeof(1L)=8 ≠ sizeof(long)=4 自相
/// 矛盾，任一真值平台口径下都不一致）。锚在**修前代码**下必红，随本
/// 批 scanner（number.mbt text 带 l/ll 尾承载分量——病 62 "ull" 同款
/// 模式）+ parser（expr.mbt 后缀分流）落地转绿。

///|
/// 红锚 M04-A1（t01 形态）：`(1 ? 1, 2 : 3)`——then 是完整 expression
///（含逗号），修前 then 调 parse_ternary（条件层）拒逗号（E2005 预期
/// ':' 级联；Win clang / WSL gcc/clang 四真值全收输出 2）。t06 嵌套赋值
/// 同根。锁 then 分支的 BinaryOp::Comma 结构。
test "m04_red_ternary_then_accepts_comma" {
  let toks = [
    tok(LParen, "(", 1, 1),
    tok(Number, "1", 1, 2),
    tok(Question, "?", 1, 4),
    tok(Number, "1", 1, 6),
    tok(Comma, ",", 1, 7),
    tok(Number, "2", 1, 9),
    tok(Colon, ":", 1, 11),
    tok(Number, "3", 1, 13),
    tok(RParen, ")", 1, 14),
    tok(Semicolon, ";", 1, 15),
    tok(Eof, "", 1, 16),
  ]
  let q = Parser::with_mode(toks, false)
  let e = q.parse_expression(0)
  guard e is @ast.Expr::Ternary(_, then_b, else_b, _, _) else {
    fail("应为 Ternary")
  }
  guard then_b is @ast.Expr::Binary(@ast.BinaryOp::Comma, _, _, _, _) else {
    fail(
      "then 分支应为逗号表达式（C11 §6.5.15 then 是完整 expression）",
    )
  }
  guard else_b is @ast.Expr::Literal(3, _, _) else {
    fail("else 分支应为字面量 3")
  }
  assert_eq(
    q.errors.length(),
    0,
    msg="合法逗号表达式不得报错（实得 \{q.errors.length()} 条）",
  )
}

///|
/// 红锚 M04-A2（l01 值域矩阵）：L 后缀（无 ll 分量）定型与 long 同宽
///（vitro LLP64：long = int 4B）——`1l` 定型 int；ll 分量照旧 long_long
///（8B）；`3000000000l` 超 LLP64 long 值域按 §6.4.4.1 值域阶递升
/// long_long。token text 为 scanner 修后形态（带 l/ll 尾承载分量——
/// 修前 scanner 剥尾、parser 一律 long_long，本锚在修前 parse_int64
/// 对带尾 text 报错即红）。
test "m04_red_l_suffix_literal_typing" {
  // 1l → Literal + int（= long 4B；修前 LongLiteral + long_long 8B）
  let q1 = Parser::with_mode(
    [tok(LongLiteral, "1l", 1, 1), tok(Eof, "", 1, 3)],
    false,
  )
  match q1.parse_expression(0) {
    Literal(v, _, ty) => {
      inspect(v, content="1")
      assert_true(
        ty is Int(false, _),
        msg="1l 应定型 int（=long 4B 口径）",
      )
    }
    _ => fail("1l 应为 Literal（i32 域内）")
  }
  assert_eq(q1.errors.length(), 0, msg="1l 合法不得报错")
  // 1ll → LongLiteral + long_long 照旧（8B）
  let q2 = Parser::with_mode(
    [tok(LongLiteral, "1ll", 1, 1), tok(Eof, "", 1, 4)],
    false,
  )
  match q2.parse_expression(0) {
    LongLiteral(v, _, ty) => {
      inspect(v, content="1")
      assert_true(ty is LongLong(_, _), msg="1ll 应定型 long long（8B）")
    }
    _ => fail("1ll 应为 LongLiteral")
  }
  assert_eq(q2.errors.length(), 0, msg="1ll 合法不得报错")
  // 3000000000l（> LLP64 LONG_MAX）→ 值域阶递升 long_long（8B）
  let q3 = Parser::with_mode(
    [tok(LongLiteral, "3000000000l", 1, 1), tok(Eof, "", 1, 12)],
    false,
  )
  match q3.parse_expression(0) {
    LongLiteral(v, _, ty) => {
      inspect(v, content="3000000000")
      assert_true(
        ty is LongLong(_, _),
        msg="3000000000l 超 LLP64 long 值域应递升 long long",
      )
    }
    _ => fail("3000000000l 应为 LongLiteral")
  }
  assert_eq(q3.errors.length(), 0, msg="3000000000l 合法不得报错")
}
