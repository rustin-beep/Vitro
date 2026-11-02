///|
/// M09 审阅红锚入库（审阅 v2 批 B9/#433，2026-11-02）：4 条锚在**修前代码**
/// 下必红（缺陷实锤，J9 证红义务），随本批处方落地转绿——转绿后即为回归锚。
/// 来源：tmp/review_v2_M09/m09_probe_wbtest.mbt（审阅现场，不入库）；
/// 处方见批内 decl.mbt（A1 is_static~ / A3 body_has_own_break）与
/// init.mbt（A2 union brace elision / A4 W3005 后置）。
///
/// 红锚 1（P1）：`static int a = 1, b = n;` 的 extra 变量丢 static 轨——
/// dispatch_stmt 对 extra 传 is_static=false ⇒ (a) 符号 is_static 位错
/// (b) 初始化器非常量 E3075 漏报（clang/gcc 三编译器均 error；
/// C11 §6.7.1 存储类说明符作用于整条声明）。
test "m09_red_static_extra_loses_storage_class" {
  let loc = @source.SourceLoc::new(3, 3)
  let tc = TypeChecker::new()
  tc.enter_scope()
  // int n = 5;
  ignore(
    tc.dispatch_stmt(
      @ast.Stmt::VarDecl(
        @ast.Type::int(),
        "n",
        Some(@ast.Expr::Literal(5, loc, @ast.Type::int())),
        [],
        false,
        false,
        loc,
      ),
    ),
  )
  // static int a = 1, b = n;
  ignore(
    tc.dispatch_stmt(
      @ast.Stmt::VarDecl(
        @ast.Type::int(),
        "a",
        Some(@ast.Expr::Literal(1, loc, @ast.Type::int())),
        [
          {
            var_type: @ast.Type::int(),
            name: "b",
            init: Some(@ast.Expr::Identifier("n", loc, @ast.Type::void_type())),
          },
        ],
        true,
        false,
        loc,
      ),
    ),
  )
  // (a) 符号面：b 应与 a 同为 static（C11 §6.7.1 存储类作用整条声明）
  match tc.lookup_var("b") {
    Some(sym) =>
      assert_true(sym.is_static, msg="extra 变量 b 的 is_static 应为 true")
    None => fail("b 未登记")
  }
  // (b) 诊断面：b = n 非常量初始化 static ⇒ 应报 E3075
  assert_true(
    tc.errors.exists(e => e.code == 3075),
    msg="static extra 变量非常量初始化应报 E3075（实得 \{tc.errors.length()} 条 error）",
  )
}

///|
/// 红锚 2（P2）：always_returns 的 break 判据不区分循环层级——
/// `while(1){ while(c){ break; } }` 内层 break 只跳内层，外层仍是无限
/// 循环（不落尾），clang/gcc -Wall -Wextra 零警；修前 stmt_contains_break
/// 把内层 break 算到外层 ⇒ W3084 假阳性（M09-A3 形态一）。
test "m09_red_nested_break_not_outer_exit" {
  let loc = @source.SourceLoc::new(2, 3)
  let one = @ast.Expr::Literal(1, loc, @ast.Type::int())
  let c = @ast.Expr::Identifier("c", loc, @ast.Type::int())
  let inner = @ast.Stmt::While(
    c,
    @ast.Stmt::Block([@ast.Stmt::Break(loc)], loc),
    loc,
  )
  let outer = @ast.Stmt::While(one, @ast.Stmt::Block([inner], loc), loc)
  assert_true(
    always_returns(outer),
    msg="外层 while(1) 无自身 break ⇒ 不落尾 ⇒ 应判「必不返回/不需 return」",
  )
}

///|
/// 红锚 2b（P2c）：`while(1){ return 1; break; }` break 在 return 之后不可达
/// ——三编译器零警，修前判「含 break」⇒ W3084 假阳性（M09-A3 形态二；
/// Block 序扫遇 Return 即停的处方语义）。
test "m09_red_unreachable_break_after_return" {
  let loc = @source.SourceLoc::new(2, 3)
  let one = @ast.Expr::Literal(1, loc, @ast.Type::int())
  let body = @ast.Stmt::Block(
    [@ast.Stmt::Return(Some(one), loc), @ast.Stmt::Break(loc)],
    loc,
  )
  let outer = @ast.Stmt::While(one, body, loc)
  assert_true(always_returns(outer), msg="return 先于 break ⇒ 必返回")
}

///|
/// 红锚 3（P1）：struct 内**具名 union** 字段的 brace elision——
/// `struct S { union U u; int x; } s = {1,2,3,4};`（U 首成员 int[3]）
/// clang/gcc 接受（仅 -Wmissing-braces，s.x==4；C11 §6.7.9p17/p20——
/// union 是聚合，扁平流按首成员吃 3 个）；修前 can_elide 的聚合字段
/// 触发条件漏 TK_Union ⇒ 不重组 ⇒ union 字段收标量报 E3006 硬拒
/// （M09-A2；clang 探针 tmp/review_v2_M09/probes/p5_union_leaf.c）。
test "m09_red_named_union_field_brace_elision" {
  let loc = @source.SourceLoc::new(4, 3)
  fn lit(v : Int32) -> @ast.InitElement {
    { designators: [], value: @ast.Expr::Literal(v, loc, @ast.Type::int()), }
  }
  let u_decl : @ast.StructDecl = {
    loc,
    name: "U",
    fields: [
      { ty: @ast.Type::array_of(@ast.Type::int(), [3]), name: "a", },
      { ty: @ast.Type::char(), name: "c", },
    ],
    is_forward: false,
  }
  let s_decl : @ast.StructDecl = {
    loc,
    name: "S",
    fields: [
      { ty: @ast.Type::union_type("U"), name: "u", },
      { ty: @ast.Type::int(), name: "x", },
    ],
    is_forward: false,
  }
  let g : @ast.GlobalDecl = {
    ..Default::default(),
    loc,
    ty: @ast.Type::struct_type("S"),
    name: "s",
    init: Some(
      @ast.Expr::InitList(
        [lit(1), lit(2), lit(3), lit(4)],
        loc,
        @ast.Type::void_type(),
      ),
    ),
    source_file: "t.c",
  }
  let prog : @ast.ProgramNode = {
    structs: [s_decl],
    unions: [u_decl],
    globals: [g],
    funcs: [],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(prog)
  assert_eq(
    errs.length(),
    0,
    msg="具名 union 字段 brace elision 合法（clang/gcc 接受），不得 E3006（实得 \{errs.length()}）",
  )
}
