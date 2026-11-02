///|
/// #426 B3' 批 2 红锚（M08 A7 类型面三处 + A8 浮点 case 占位）——ops.mbt
/// 一元/移位定型接共享核 integer_promote 前红、接后绿。J9 先红后修。
///
/// A7 的病理与 A1 不同：**定型面**错 → 折叠与运行期一起错（A1 式「折叠↔
/// 运行期分叉」探针测不出），必须对拍 clang 真值（M08 §3.1 #8-11 四端一致）。
/// 批 1 已把求值域与定型面解耦（CE_AppU 按操作数提升），故本批修定型后
/// 下游比较（lty = 定型结果）随之正确——值锚经静态初始化器折叠断言。

///|
/// A7.1：Shl/Shr 的 unsigned char 左操作数应提升 **signed int**（C11
/// §6.3.1.1）；旧 `Int(left.is_unsigned())` 定 unsigned int。
/// 类型锚 + 值锚 `((unsigned char)255 << 24) < 0` → 1（真值四端一致）。
test "a7_shl_uchar_promotes_signed_int" {
  let loc = @source.SourceLoc::new(1, 1)
  let uchar = @ast.Type::Char(true, false)
  let tc = TypeChecker::new()
  let (ty, _) = tc.resolve_binary(
    Shl,
    @ast.Expr::Literal(1, loc, uchar),
    @ast.Expr::Literal(1, loc, @ast.Type::int()),
    loc,
  )
  assert_true(ty is Int(_, _), msg="uchar << int 结果 kind=int")
  assert_false(
    ty.is_unsigned(),
    msg="uchar 提升 signed int——unsigned 位消失（M08 锚盲区补断言）",
  )
  // 值锚：((unsigned char)255 << 24) < 0 == 1
  let shl = @ast.Expr::Binary(
    Shl,
    @ast.Expr::Cast(
      @ast.Expr::Literal(255, loc, @ast.Type::int()),
      uchar,
      loc,
      uchar,
    ),
    @ast.Expr::Literal(24, loc, @ast.Type::int()),
    loc,
    @ast.Type::int(),
  )
  let cmp = @ast.Expr::Binary(
    Lt,
    shl,
    @ast.Expr::Literal(0, loc, @ast.Type::int()),
    loc,
    @ast.Type::int(),
  )
  let tc2 = TypeChecker::new()
  let (typed, errs, _, _) = tc2.check(
    gprog([gdecl(@ast.Type::int(), "t1", Some(cmp))]),
  )
  assert_eq(errs.length(), 0)
  assert_eq(
    m08_folded(typed, 0),
    Some(1L),
    msg="((uchar)255<<24)<0 应为 1（移位结果为负 int）",
  )
}

///|
/// A7.2：BitNot 应保持 unsigned int（`~0u` 是 unsigned）；旧非 LL 一律
/// signed int。类型锚 + 值锚 `(~0u) < 0` → 0、`(~0u) > 0` → 1。
test "a7_bitnot_keeps_unsigned_int" {
  let loc = @source.SourceLoc::new(1, 1)
  let tc = TypeChecker::new()
  let (ty, _) = tc.resolve_unary(
    BitNot,
    @ast.Expr::Literal(0, loc, @ast.Type::unsigned_int()),
    loc,
  )
  assert_true(ty is Int(_, _))
  assert_true(
    ty.is_unsigned(),
    msg="~0u 定型 unsigned int（旧恒 signed int）",
  )
  fn not0u() -> @ast.Expr {
    @ast.Expr::Unary(
      BitNot,
      @ast.Expr::Literal(0, loc, @ast.Type::unsigned_int()),
      loc,
      @ast.Type::unsigned_int(),
    )
  }
  let lt = @ast.Expr::Binary(
    Lt,
    not0u(),
    @ast.Expr::Literal(0, loc, @ast.Type::int()),
    loc,
    @ast.Type::int(),
  )
  let gt = @ast.Expr::Binary(
    Gt,
    not0u(),
    @ast.Expr::Literal(0, loc, @ast.Type::int()),
    loc,
    @ast.Type::int(),
  )
  let tc2 = TypeChecker::new()
  let (typed, errs, _, _) = tc2.check(
    gprog([
      gdecl(@ast.Type::int(), "a", Some(lt)),
      gdecl(@ast.Type::int(), "b", Some(gt)),
    ]),
  )
  assert_eq(errs.length(), 0)
  assert_eq(
    m08_folded(typed, 0),
    Some(0L),
    msg="(~0u)<0 应为 0（真值四端一致；旧 1）",
  )
  assert_eq(m08_folded(typed, 1), Some(1L), msg="(~0u)>0 应为 1（旧 0）")
}

///|
/// A7.3：Neg 的 unsigned char 操作数应提升 **signed int**（旧按 is_unsigned
/// 归 unsigned int）；LL 分支应保留 unsigned 位（`-1ULL` 定型 unsigned LL，
/// 旧 `long_long()` 丢位——M08 推断 P2 面在此立锚）。
/// 值锚 `(-(unsigned char)1) < 0` → 1。
test "a7_neg_promotes_uchar_and_keeps_ull" {
  let loc = @source.SourceLoc::new(1, 1)
  let uchar = @ast.Type::Char(true, false)
  let ull = @ast.Type::LongLong(true, false)
  let tc = TypeChecker::new()
  let (ty_uc, _) = tc.resolve_unary(Neg, @ast.Expr::Literal(1, loc, uchar), loc)
  assert_true(ty_uc is Int(_, _), msg="-(uchar) 结果 kind=int")
  assert_false(
    ty_uc.is_unsigned(),
    msg="-(uchar) 提升 signed int（旧 unsigned int）",
  )
  let (ty_ull, _) = tc.resolve_unary(
    Neg,
    @ast.Expr::LongLiteral(1L, loc, ull),
    loc,
  )
  assert_true(ty_ull is LongLong(_, _))
  assert_true(
    ty_ull.is_unsigned(),
    msg="-1ULL 定型 unsigned long long（旧丢 unsigned 位）",
  )
  // 值锚
  let neg = @ast.Expr::Unary(
    Neg,
    @ast.Expr::Cast(
      @ast.Expr::Literal(1, loc, @ast.Type::int()),
      uchar,
      loc,
      uchar,
    ),
    loc,
    @ast.Type::int(),
  )
  let cmp = @ast.Expr::Binary(
    Lt,
    neg,
    @ast.Expr::Literal(0, loc, @ast.Type::int()),
    loc,
    @ast.Type::int(),
  )
  let tc2 = TypeChecker::new()
  let (typed, errs, _, _) = tc2.check(
    gprog([gdecl(@ast.Type::int(), "n1", Some(cmp))]),
  )
  assert_eq(errs.length(), 0)
  assert_eq(
    m08_folded(typed, 0),
    Some(1L),
    msg="(-(uchar)1)<0 应为 1（旧 0）",
  )
}

///|
/// A8：浮点 case 标签各报一条 E3047 即可；旧两个浮点 case 在查重表共占
/// 位 0 互撞多报一条假 E3074「重复的 case 值 0」（源码里没有 0，教学误导）。
test "a8_float_case_labels_no_phantom_dup" {
  let loc = @source.SourceLoc::new(2, 5)
  fn fcase(v : Double) -> @ast.Stmt {
    @ast.Stmt::Case(
      Some(@ast.Expr::FloatLiteral(v, loc, @ast.Type::double())),
      @ast.Stmt::Expr(@ast.Expr::Literal(0, loc, @ast.Type::int()), loc),
      loc,
    )
  }
  let sw = @ast.Stmt::Switch(
    @ast.Expr::Literal(1, loc, @ast.Type::int()),
    @ast.Stmt::Block([fcase(1.5), fcase(2.5)], loc),
    loc,
  )
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(
    gprog([]) |> with_main(@ast.Stmt::Block([sw], loc)),
  )
  let e3047 = errs.filter(e => e.code == 3047).length()
  let e3074 = errs.filter(e => e.code == 3074).length()
  assert_eq(e3047, 2, msg="两个浮点 case 各报一条 E3047")
  assert_eq(
    e3074,
    0,
    msg="不应有假 E3074「重复 case 值 0」（旧 1 条）",
  )
}
