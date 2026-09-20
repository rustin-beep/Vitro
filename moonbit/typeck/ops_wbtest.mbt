///|
/// resolve_binary 关键面（promote / 指针算术 / 比较定型 / 逗号右值 /
/// 移位左提升；改判据此锚红）。
test "resolve_binary_key_shapes" {
  let loc = @source.SourceLoc::new(1, 5)
  let tc = TypeChecker::new()
  tc.enter_scope()
  fn lit(v : Int) -> @ast.Expr {
    @ast.Expr::Literal(v, loc, @ast.Type::int())
  }
  fn flit(v : Double) -> @ast.Expr {
    @ast.Expr::FloatLiteral(v, loc, @ast.Type::double())
  }
  // int + double → double
  let (ty, e) = tc.resolve_binary(Add, lit(1), flit(2.0), loc)
  assert_true(ty is Double(_))
  match e {
    Binary(Add, _, _, _, t) => assert_true(t is Double(_))
    _ => fail("Binary 重建形态")
  }
  // int + int → int
  let (ty2, _) = tc.resolve_binary(Mul, lit(3), lit(4), loc)
  assert_true(ty2 is Int(_, _))
  // 指针 + 整数 → 指针；数组 + 整数 → decay 到元素指针
  tc.declare_var(
    "p",
    @ast.Type::pointer_to(@ast.Type::int()),
    is_global=false,
    is_extern=false,
    is_static=false,
  )
  tc.declare_var(
    "arr",
    @ast.Type::array_of(@ast.Type::int(), [4]),
    is_global=false,
    is_extern=false,
    is_static=false,
  )
  let pid = @ast.Expr::Identifier("p", loc, @ast.Type::void_type())
  let (ty3, _) = tc.resolve_binary(Add, pid, lit(2), loc)
  match ty3 {
    Pointer(pointee, _) => assert_true(pointee is Int(_, _))
    _ => fail("指针+整数应保持指针")
  }
  let aid = @ast.Expr::Identifier("arr", loc, @ast.Type::void_type())
  let (ty3b, _) = tc.resolve_binary(Add, aid, lit(2), loc)
  match ty3b {
    Pointer(pointee, _) => assert_true(pointee is Int(_, _))
    _ => fail("数组+整数应 decay 到元素指针")
  }
  // 比较 → int
  let (ty4, _) = tc.resolve_binary(Lt, lit(1), lit(2), loc)
  assert_true(ty4 is Int(_, _))
  // 逗号 → 右值类型
  let (ty5, _) = tc.resolve_binary(Comma, lit(1), flit(2.0), loc)
  assert_true(ty5 is Double(_))
  // 移位：char 左操作数提升 int
  let (ty6, _) = tc.resolve_binary(
    Shl,
    @ast.Expr::Literal(1, loc, @ast.Type::char()),
    lit(1),
    loc,
  )
  assert_true(ty6 is Int(_, _))
  assert_eq(tc.errors.length(), 0)
}

///|
/// 三目 decay（`" "` 与 `""` 统一 char*——勘察 §6 语境的防线）与分支
/// 不匹配 E3004。
test "resolve_ternary_decay" {
  let loc = @source.SourceLoc::new(2, 3)
  let tc = TypeChecker::new()
  let s1 = @ast.Expr::StringLiteral(" ", loc, @ast.Type::void_type())
  let s2 = @ast.Expr::StringLiteral("", loc, @ast.Type::void_type())
  let cond = @ast.Expr::Literal(1, loc, @ast.Type::int())
  let (ty, _) = tc.resolve_ternary(cond, s1, s2, loc)
  match ty {
    Pointer(pointee, _) => assert_true(pointee is Char(_, _))
    _ => fail("两 char 数组三目应 decay 统一 char*")
  }
  assert_eq(tc.errors.length(), 0)
  // 分支不匹配：int vs double——decay 后仍异 → E3004
  let lit = @ast.Expr::Literal(1, loc, @ast.Type::int())
  let flit = @ast.Expr::FloatLiteral(2.0, loc, @ast.Type::double())
  let _ = tc.resolve_ternary(cond, lit, flit, loc)
  assert_eq(tc.errors.length(), 1)
  assert_true(tc.errors[0].code == 3004)
}

///|
/// 一元（取址/解引用互逆 + 宽度保留 + 自增 const 检查 E3049）。
test "resolve_unary_shapes" {
  let loc = @source.SourceLoc::new(1, 1)
  let tc = TypeChecker::new()
  tc.enter_scope()
  tc.declare_var(
    "n",
    @ast.Type::int(),
    is_global=false,
    is_extern=false,
    is_static=false,
  )
  // 取址 → int*；再解引用 → int（互逆）
  let id = @ast.Expr::Identifier("n", loc, @ast.Type::void_type())
  let (pty, _) = tc.resolve_unary(Addr, id, loc)
  match pty {
    Pointer(pointee, _) => assert_true(pointee is Int(_, _))
    _ => fail("取址应得指针")
  }
  let id2 = @ast.Expr::Identifier("n", loc, @ast.Type::void_type())
  let (dty, _) = tc.resolve_unary(
    Deref,
    @ast.Expr::Unary(Addr, id2, loc, pty),
    loc,
  )
  assert_true(dty is Int(_, _))
  // 取负宽度保留：double → double；long long → long long
  let flit = @ast.Expr::FloatLiteral(2.0, loc, @ast.Type::double())
  let (nt, _) = tc.resolve_unary(Neg, flit, loc)
  assert_true(nt is Double(_))
  let llit = @ast.Expr::LongLiteral(2L, loc, @ast.Type::long_long())
  let (nt2, _) = tc.resolve_unary(Neg, llit, loc)
  assert_true(nt2 is LongLong(_, _))
  // 自增 const：E3049
  tc.declare_var(
    "c",
    @ast.Type::int().set_const(true),
    is_global=false,
    is_extern=false,
    is_static=false,
  )
  let cid = @ast.Expr::Identifier("c", loc, @ast.Type::void_type())
  let _ = tc.resolve_unary(PostInc, cid, loc)
  assert_eq(tc.errors.length(), 1)
  assert_true(tc.errors[0].code == 3049)
}

///|
/// 赋值（左值判定 E3043 / check_assignable E3044 / **Cast 插入 lowering**
/// / 指针复合赋值特判）。
test "resolve_assign_shapes" {
  let loc = @source.SourceLoc::new(3, 1)
  let tc = TypeChecker::new()
  tc.enter_scope()
  tc.declare_var(
    "d",
    @ast.Type::double(),
    is_global=false,
    is_extern=false,
    is_static=false,
  )
  tc.declare_var(
    "i",
    @ast.Type::int(),
    is_global=false,
    is_extern=false,
    is_static=false,
  )
  // d = 1（int→double）：insert_implicit_cast → Cast 包裹（lowering 锚）
  let lhs = @ast.Expr::Identifier("d", loc, @ast.Type::void_type())
  let rhs = @ast.Expr::Literal(1, loc, @ast.Type::int())
  let (ty, e) = tc.resolve_assign(Assign, lhs, rhs, loc)
  assert_true(ty is Double(_))
  match e {
    Assign(Assign, _, right, _, _) =>
      match right {
        Cast(_, target, _, t) => {
          assert_true(target is Double(_))
          assert_true(t is Double(_))
        }
        _ => fail("int→double 赋值右值应包 Cast")
      }
    _ => fail("Assign 重建形态")
  }
  assert_eq(tc.errors.length(), 0)
  // 类型不匹配：int 左值 = double 右值会插 Cast（可赋值）——用字符串测
  // E3044：int = char 数组不可赋值
  let lhs2 = @ast.Expr::Identifier("i", loc, @ast.Type::void_type())
  let rhs2 = @ast.Expr::StringLiteral("x", loc, @ast.Type::void_type())
  let _ = tc.resolve_assign(Assign, lhs2, rhs2, loc)
  assert_eq(tc.errors.length(), 1)
  assert_true(tc.errors[0].code == 3044)
  // 非左值：字面量左值 E3043
  let lit = @ast.Expr::Literal(1, loc, @ast.Type::int())
  let _ = tc.resolve_assign(Assign, lit, lit, loc)
  assert_eq(tc.errors.length(), 2)
  assert_true(tc.errors[1].code == 3043)
  // 指针 += 整数：跳过兼容检查（合法，无新错）
  tc.declare_var(
    "p",
    @ast.Type::pointer_to(@ast.Type::int()),
    is_global=false,
    is_extern=false,
    is_static=false,
  )
  let plhs = @ast.Expr::Identifier("p", loc, @ast.Type::void_type())
  let _ = tc.resolve_assign(
    AddAssign,
    plhs,
    @ast.Expr::Literal(2, loc, @ast.Type::int()),
    loc,
  )
  assert_eq(tc.errors.length(), 2)
}

///|
/// _Generic 选择（decay 匹配 char* 关联；无匹配无 default → E3004；
/// default 兜底）。
test "resolve_generic_selection" {
  let loc = @source.SourceLoc::new(1, 1)
  let tc = TypeChecker::new()
  // 控制表达式 char 数组 → decay char* → 命中 char* 关联
  let ctrl = @ast.Expr::StringLiteral("x", loc, @ast.Type::void_type())
  let assoc_int = @ast.Expr::Literal(1, loc, @ast.Type::int())
  let assoc_charp = @ast.Expr::Literal(2, loc, @ast.Type::int())
  let (ty, _) = tc.resolve_generic(
    ctrl,
    [
      (@ast.Type::int(), assoc_int),
      (@ast.Type::pointer_to(@ast.Type::char()), assoc_charp),
    ],
    None,
    loc,
  )
  assert_true(ty is Int(_, _))
  assert_eq(tc.errors.length(), 0)
  // 无匹配无 default → E3004
  let ctrl2 = @ast.Expr::StringLiteral("x", loc, @ast.Type::void_type())
  let _ = tc.resolve_generic(
    ctrl2,
    [(@ast.Type::int(), @ast.Expr::Literal(1, loc, @ast.Type::int()))],
    None,
    loc,
  )
  assert_eq(tc.errors.length(), 1)
  assert_true(tc.errors[0].code == 3004)
  // default 兜底
  let ctrl3 = @ast.Expr::StringLiteral("x", loc, @ast.Type::void_type())
  let (ty3, _) = tc.resolve_generic(
    ctrl3,
    [(@ast.Type::int(), @ast.Expr::Literal(1, loc, @ast.Type::int()))],
    Some(@ast.Expr::FloatLiteral(1.0, loc, @ast.Type::double())),
    loc,
  )
  assert_true(ty3 is Double(_))
  assert_eq(tc.errors.length(), 1) // 无新错
}
