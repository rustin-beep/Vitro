///|
/// T5-b/c decl 面白盒锚：语句族防线（Return 三面 / Break-Continue 守卫 /
/// goto-label 闭合）/ typeof 推导替换 / 条件检查（W3050 / W3051）。

///|
/// 空程序根。
fn empty_prog(funcs : Array[@ast.FuncDecl]) -> @ast.ProgramNode {
  {
    structs: [],
    unions: [],
    globals: [],
    funcs,
    classes: [],
    templates: [],
    template_instantiations: [],
  }
}

///|
/// main 包装（body 注入）。
fn main_of(body : @ast.Stmt) -> @ast.FuncDecl {
  let loc = @source.SourceLoc::new(1, 1)
  {
    loc,
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(body),
    is_static: false,
    is_extern: false,
    source_file: "t.c",
    is_variadic: false,
  }
}

///|
/// Return 三面：void 函数带值 E3012 / 非 void 缺值 E3013 / 返回类型
/// 不匹配 E3014。
test "stmt_return_checks" {
  let loc = @source.SourceLoc::new(2, 5)
  let one = @ast.Expr::Literal(1, loc, @ast.Type::int())
  // void 函数 return 1 → E3012
  let void_main : @ast.FuncDecl = {
    ..main_of(@ast.Stmt::Return(Some(one), loc)),
    return_type: @ast.Type::void_type(),
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(empty_prog([void_main]))
  assert_eq(errs.length(), 1)
  assert_true(errs[0].code == 3012)
  // int 函数裸 return → E3013
  let tc2 = TypeChecker::new()
  let (_, errs2, _, _) = tc2.check(
    empty_prog([main_of(@ast.Stmt::Return(None, loc))]),
  )
  assert_eq(errs2.length(), 1)
  assert_true(errs2[0].code == 3013)
  // int 函数 return &x（int*→int 不可赋值）→ E3014
  let addr : @ast.Expr = @ast.Expr::Unary(
    Addr,
    @ast.Expr::Identifier("x", loc, @ast.Type::int()),
    loc,
    @ast.Type::void_type(),
  )
  let tc3 = TypeChecker::new()
  let (_, errs3, _, _) = tc3.check(
    empty_prog([
      main_of(
        @ast.Stmt::Block(
          [
            @ast.Stmt::VarDecl(@ast.Type::int(), "x", None, [], false, loc),
            @ast.Stmt::Return(Some(addr), loc),
          ],
          loc,
        ),
      ),
    ]),
  )
  assert_eq(errs3.length(), 1)
  assert_true(errs3[0].code == 3014)
}

///|
/// Break/Continue 守卫：裸 break → E3010、裸 continue → E3011；循环内
/// 合法（while 体）。
test "stmt_break_continue_guards" {
  let loc = @source.SourceLoc::new(2, 5)
  fn run(body : @ast.Stmt) -> Array[@diag.ErrorCode] {
    ignore(body)
    []
  }
  ignore(run)
  // 裸 break/continue
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(
    empty_prog([
      main_of(
        @ast.Stmt::Block([@ast.Stmt::Break(loc), @ast.Stmt::Continue(loc)], loc),
      ),
    ]),
  )
  assert_eq(errs.length(), 2)
  assert_true(errs[0].code == 3010)
  assert_true(errs[1].code == 3011)
  // while 循环体内合法
  let cond = @ast.Expr::Literal(1, loc, @ast.Type::int())
  let tc2 = TypeChecker::new()
  let (_, errs2, _, _) = tc2.check(
    empty_prog([
      main_of(
        @ast.Stmt::While(
          cond,
          @ast.Stmt::Block(
            [@ast.Stmt::Break(loc), @ast.Stmt::Continue(loc)],
            loc,
          ),
          loc,
        ),
      ),
    ]),
  )
  assert_eq(errs2.length(), 0)
}

///|
/// goto/label 闭合：未定义 goto → E3071；重复 label → E3001；已定义
/// goto 无错。
test "stmt_goto_label_closure" {
  let loc = @source.SourceLoc::new(2, 5)
  // goto end; ... end: （合法闭合）
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(
    empty_prog([
      main_of(
        @ast.Stmt::Block(
          [
            @ast.Stmt::Goto("end", loc),
            @ast.Stmt::Label(
              "end",
              @ast.Stmt::Expr(@ast.Expr::Literal(0, loc, @ast.Type::int()), loc),
              loc,
            ),
          ],
          loc,
        ),
      ),
    ]),
  )
  assert_eq(errs.length(), 0)
  // 未定义 goto nowhere → E3071
  let tc2 = TypeChecker::new()
  let (_, errs2, _, _) = tc2.check(
    empty_prog([
      main_of(@ast.Stmt::Block([@ast.Stmt::Goto("nowhere", loc)], loc)),
    ]),
  )
  assert_eq(errs2.length(), 1)
  assert_true(errs2[0].code == 3071)
  // 重复 label → E3001
  let lab = @ast.Stmt::Label(
    "dup",
    @ast.Stmt::Expr(@ast.Expr::Literal(0, loc, @ast.Type::int()), loc),
    loc,
  )
  let tc3 = TypeChecker::new()
  let (_, errs3, _, _) = tc3.check(
    empty_prog([main_of(@ast.Stmt::Block([lab, lab], loc))]),
  )
  assert_eq(errs3.length(), 1)
  assert_true(errs3[0].code == 3001)
}

///|
/// typeof 推导（C 面真实消费——gap/typeof_operator.c 族）：`typeof(x) y`
/// 声明类型替换为 x 的 int；未初始化 typeof 走 Typeof 内联表达式轨。
test "var_typeof_deduce" {
  let loc = @source.SourceLoc::new(2, 5)
  let typeof_int : @ast.Type = @ast.Type::Typeof(
    @ast.Expr::Identifier("x", loc, @ast.Type::void_type()),
    false,
    false,
  )
  let body : @ast.Stmt = @ast.Stmt::Block(
    [
      @ast.Stmt::VarDecl(@ast.Type::int(), "x", None, [], false, loc),
      @ast.Stmt::VarDecl(
        typeof_int,
        "y",
        Some(@ast.Expr::Identifier("x", loc, @ast.Type::void_type())),
        [],
        false,
        loc,
      ),
    ],
    loc,
  )
  let tc = TypeChecker::new()
  let (typed, errs, _, _) = tc.check(empty_prog([main_of(body)]))
  assert_eq(errs.length(), 0)
  match typed.funcs[0].body {
    Some(Block(stmts, _)) =>
      match stmts[1] {
        VarDecl(ty, "y", _, _, _, _) => assert_true(ty is Int(_, _)) // typeof(x) → int 替换
        _ => fail("y 声明")
      }
    _ => fail("body")
  }
}

///|
/// 条件检查两面：`if (x = 5)` 赋值条件 W3050；`for (i=0; i<=n; i++)`
/// 索引数组 W3051（Le + 数组参与）。
test "condition_warnings" {
  let loc = @source.SourceLoc::new(2, 5)
  let five = @ast.Expr::Literal(5, loc, @ast.Type::int())
  // if (x = 5)
  let assign_cond : @ast.Expr = @ast.Expr::Assign(
    @ast.AssignOp::Assign,
    @ast.Expr::Identifier("x", loc, @ast.Type::int()),
    five,
    loc,
    @ast.Type::void_type(),
  )
  let body : @ast.Stmt = @ast.Stmt::Block(
    [
      @ast.Stmt::VarDecl(@ast.Type::int(), "x", None, [], false, loc),
      @ast.Stmt::If(assign_cond, @ast.Stmt::Block([], loc), None, loc),
    ],
    loc,
  )
  let tc = TypeChecker::new()
  let (_, _, warns, _) = tc.check(empty_prog([main_of(body)]))
  assert_eq(warns.length(), 1)
  assert_true(warns[0].code == 3050)
  // for (i=0; i<=9; i++) a[i] —— 数组索引 Le → W3051
  let idx : @ast.Expr = @ast.Expr::Index(
    @ast.Expr::Identifier("a", loc, @ast.Type::void_type()),
    @ast.Expr::Identifier("i", loc, @ast.Type::int()),
    loc,
    @ast.Type::void_type(),
  )
  // W3051 判据是**条件两侧**含数组/指针表达式（Rust 同构——body 内的
  // a[i] 不参与判定）；构造 i <= a[0]
  let le : @ast.Expr = @ast.Expr::Binary(
    Le,
    @ast.Expr::Identifier("i", loc, @ast.Type::int()),
    @ast.Expr::Index(
      @ast.Expr::Identifier("a", loc, @ast.Type::void_type()),
      @ast.Expr::Literal(0, loc, @ast.Type::int()),
      loc,
      @ast.Type::void_type(),
    ),
    loc,
    @ast.Type::void_type(),
  )
  let for_stmt : @ast.Stmt = @ast.Stmt::For(
    Some(@ast.Stmt::VarDecl(@ast.Type::int(), "i", None, [], false, loc)),
    Some(le),
    [],
    @ast.Stmt::Expr(idx, loc),
    loc,
  )
  let body2 : @ast.Stmt = @ast.Stmt::Block(
    [
      @ast.Stmt::VarDecl(
        @ast.Type::array_of(@ast.Type::int(), [10]),
        "a",
        None,
        [],
        false,
        loc,
      ),
      for_stmt,
    ],
    loc,
  )
  let tc2 = TypeChecker::new()
  let (_, _, warns2, _) = tc2.check(empty_prog([main_of(body2)]))
  assert_eq(warns2.length(), 1)
  assert_true(warns2[0].code == 3051)
}
