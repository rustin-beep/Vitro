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
    ..Default::default(),
    loc,
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(body),
    source_file: "t.c",
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
            @ast.Stmt::VarDecl(
              @ast.Type::int(),
              "x",
              None,
              [],
              false,
              false,
              loc,
            ),
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
      @ast.Stmt::VarDecl(@ast.Type::int(), "x", None, [], false, false, loc),
      @ast.Stmt::VarDecl(
        typeof_int,
        "y",
        Some(@ast.Expr::Identifier("x", loc, @ast.Type::void_type())),
        [],
        false,
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
        VarDecl(ty, "y", _, _, _, _, _) => assert_true(ty is Int(_, _)) // typeof(x) → int 替换
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
      @ast.Stmt::VarDecl(@ast.Type::int(), "x", None, [], false, false, loc),
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
    Some(@ast.Stmt::VarDecl(@ast.Type::int(), "i", None, [], false, false, loc)),
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
        false,
        loc,
      ),
      for_stmt,
    ],
    loc,
  )
  let tc2 = TypeChecker::new()
  let (_, _, warns2, hints2) = tc2.check(empty_prog([main_of(body2)]))
  // 病 19（#61，2026-10-10）：「循环 <=」提示转 H 级（Clang 默认无对应——
  // W3051 只承载静态常数下标越界）
  assert_eq(warns2.length(), 0)
  assert_eq(hints2.length(), 1)
  assert_true(hints2[0].code == 3069)
}

///|
/// 病 118 锚（#71，2026-10-11；**审阅 P2 降级翻面 2026-10-13**）：条件
/// 表达式顶层的孤立位运算 `|`/`&`（常见 `||`/`&&` 误写）报教学码
///（catalog 1004 文案在案、fix_1004 区间修复已就位）。
/// **降级缘由**：`if (a > 2 | b < 1)` 是合法 C（位或作用于比较结果 0/1
/// 域）——clang 含 -Wall -Wextra 静默接受；E 级硬错拒合法 C 与 #75
/// vitro_reject_clang_accept 桶清零方向冲突 → report_error 降
/// report_warning（E1004 码位保持，severity 由 report 通道决定）。
test "cond_bitop_e1004_wiring_b118" {
  fn num(v : Int32) -> @ast.Expr {
    @ast.Expr::Literal(v, @source.SourceLoc::new(1, 5), @ast.Type::int())
  }
  fn bin(op : @ast.BinaryOp, l : @ast.Expr, r : @ast.Expr) -> @ast.Expr {
    @ast.Expr::Binary(op, l, r, @source.SourceLoc::new(1, 5), @ast.Type::int())
  }
  let loc = @source.SourceLoc::new(1, 4)
  // if (a > 0 | b > 0)：比较结果上的 | = || 误写（零歧义）应报 W 级 E1004
  fn cmp(op : @ast.BinaryOp, l : @ast.Expr, r : @ast.Expr) -> @ast.Expr {
    @ast.Expr::Binary(op, l, r, @source.SourceLoc::new(1, 5), @ast.Type::int())
  }
  let a_gt0 = cmp(Gt, num(1), num(0))
  let tc1 = TypeChecker::new()
  ignore(tc1.check_condition(bin(BitOr, a_gt0, num(2)), "if 条件", loc))
  assert_eq(
    tc1.errors.length(),
    0,
    msg="合法 C 不得硬错拒（审阅 P2）",
  )
  assert_eq(
    tc1.warnings.length(),
    1,
    msg="比较结果上的 | 须报 W 级 E1004",
  )
  assert_true(tc1.warnings[0].code == 1004)
  // & 同款
  let tc2 = TypeChecker::new()
  ignore(tc2.check_condition(bin(BitAnd, a_gt0, num(2)), "if 条件", loc))
  assert_eq(tc2.errors.length(), 0, msg="& 同款不硬错拒")
  assert_eq(
    tc2.warnings.length(),
    1,
    msg="比较结果上的 & 须报 W 级 E1004",
  )
  // 位测试习语不误伤（语料实锤回归锚：lc_50 `exp & 1` / lc_78 `mask&(1<<i)`）
  let tc6 = TypeChecker::new()
  ignore(tc6.check_condition(bin(BitAnd, num(1), num(1)), "if 条件", loc))
  assert_eq(
    tc6.errors.length() + tc6.warnings.length(),
    0,
    msg="裸位测试（exp & 1 形态）不误伤",
  )
  // 不误伤：位运算在非条件位置合法（resolve 正常）；条件内比较/逻辑或零报
  let tc3 = TypeChecker::new()
  ignore(tc3)
  // 条件内比较零报（回归面）
  let tc4 = TypeChecker::new()
  ignore(tc4.check_condition(bin(Lt, num(1), num(2)), "if 条件", loc))
  assert_eq(tc4.errors.length(), 0, msg="比较不误伤")
  // 逻辑或/与零报
  let tc5 = TypeChecker::new()
  ignore(
    tc5.check_condition(
      bin(Or, bin(Lt, num(1), num(2)), bin(Lt, num(3), num(4))),
      "if 条件",
      loc,
    ),
  )
  assert_eq(tc5.errors.length(), 0, msg="|| 不误伤")
}

///|
/// #75 缺口 2 锚（2026-10-12，C11 6.2.1p2）：声明符作用域始于初始化器
/// ——`int *p = malloc(n * sizeof *p)` 的 init 引用自身合法。predeclared
/// 前置登记（标量面）+ final 覆盖；真重声明（两语句）仍 E3001。
test "init_self_reference_scope_issue75_g2" {
  let tc = TypeChecker::new()
  tc.enter_scope()
  // `int n = 5; int *p = ... sizeof *p ...`（经 dispatch_stmt 直驱）
  let n_decl = @ast.Stmt::VarDecl(
    @ast.Type::int(),
    "n",
    Some(@ast.Expr::Literal(5, @source.SourceLoc::new(2, 9), @ast.Type::int())),
    [],
    false,
    false,
    @source.SourceLoc::new(2, 5),
  )
  ignore(tc.dispatch_stmt(n_decl))
  // p 声明：init = Cast(void*→int*) 内 Unary(Deref, p)——resolve 期
  // p 已可见（predeclared）
  let p_loc = @source.SourceLoc::new(3, 8)
  let deref_p = @ast.Expr::Unary(
    @ast.UnaryOp::Deref,
    @ast.Expr::Identifier("p", p_loc, @ast.Type::void_type()),
    p_loc,
    @ast.Type::void_type(),
  )
  let p_init = @ast.Expr::Cast(
    deref_p,
    @ast.Type::pointer_to(@ast.Type::int()),
    p_loc,
    @ast.Type::pointer_to(@ast.Type::int()),
  )
  let p_decl = @ast.Stmt::VarDecl(
    @ast.Type::pointer_to(@ast.Type::int()),
    "p",
    Some(p_init),
    [],
    false,
    false,
    @source.SourceLoc::new(3, 8),
  )
  ignore(tc.dispatch_stmt(p_decl))
  assert_eq(
    tc.errors.length(),
    0,
    msg="sizeof *p 自身引用合法（E3023 假阳性）",
  )
  // 真重声明仍拦（两语句同名）
  let dup = @ast.Stmt::VarDecl(
    @ast.Type::int(),
    "n",
    Some(@ast.Expr::Literal(7, @source.SourceLoc::new(5, 9), @ast.Type::int())),
    [],
    false,
    false,
    @source.SourceLoc::new(5, 5),
  )
  ignore(tc.dispatch_stmt(dup))
  assert_true(
    tc.errors.length() >= 1,
    msg="真重声明维持 E3001（含级联）",
  )
}

///|
/// #156：register 变量取地址 → E3078（clang "address of register variable
/// requested"，C11 §6.7.1p4 约束）。裸 Identifier 操作数形态；非 register
/// 取地址零报反向锚。
test "register_addr_of_rejected" {
  let loc = @source.SourceLoc::new(2, 5)
  // register int x = 5; int *p = &x;
  let reg_decl = @ast.Stmt::VarDecl(
    @ast.Type::int(),
    "x",
    Some(@ast.Expr::Literal(5, loc, @ast.Type::int())),
    [],
    false,
    true,
    loc,
  )
  let addr = @ast.Stmt::VarDecl(
    @ast.Type::pointer_to(@ast.Type::int()),
    "p",
    Some(
      @ast.Expr::Unary(
        @ast.UnaryOp::Addr,
        @ast.Expr::Identifier("x", loc, @ast.Type::int()),
        loc,
        @ast.Type::int(),
      ),
    ),
    [],
    false,
    false,
    loc,
  )
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(
    empty_prog([main_of(@ast.Stmt::Block([reg_decl, addr], loc))]),
  )
  assert_true(
    errs.exists(e => e.code == 3078),
    msg="register 变量取地址应报 E3078",
  )
}

///|
/// #156 反向：普通变量取地址零报（E3078 不得误伤常规 &x）。
test "plain_addr_of_allowed" {
  let loc = @source.SourceLoc::new(2, 5)
  let decl = @ast.Stmt::VarDecl(
    @ast.Type::int(),
    "x",
    Some(@ast.Expr::Literal(5, loc, @ast.Type::int())),
    [],
    false,
    false,
    loc,
  )
  let addr = @ast.Stmt::VarDecl(
    @ast.Type::pointer_to(@ast.Type::int()),
    "p",
    Some(
      @ast.Expr::Unary(
        @ast.UnaryOp::Addr,
        @ast.Expr::Identifier("x", loc, @ast.Type::int()),
        loc,
        @ast.Type::int(),
      ),
    ),
    [],
    false,
    false,
    loc,
  )
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(
    empty_prog([main_of(@ast.Stmt::Block([decl, addr], loc))]),
  )
  assert_false(
    errs.exists(e => e.code == 3078),
    msg="普通变量取地址不应报 E3078",
  )
}

///|
/// #156 作用域遮蔽：外层普通 x + 内层 register x，内层 &x 报、退层后
/// 外层 &x 不报（VarSymbol 随 scope 栈天然感知）。
test "register_shadowing_scope_aware" {
  let loc = @source.SourceLoc::new(2, 5)
  fn addr_stmt() -> @ast.Stmt {
    @ast.Stmt::Expr(
      @ast.Expr::Unary(
        @ast.UnaryOp::Addr,
        @ast.Expr::Identifier("x", loc, @ast.Type::int()),
        loc,
        @ast.Type::int(),
      ),
      loc,
    )
  }
  let plain_decl = @ast.Stmt::VarDecl(
    @ast.Type::int(),
    "x",
    None,
    [],
    false,
    false,
    loc,
  )
  let reg_decl = @ast.Stmt::VarDecl(
    @ast.Type::int(),
    "x",
    None,
    [],
    false,
    true,
    loc,
  )
  // { int x; { register int x; &x; } &x; }
  let body = @ast.Stmt::Block(
    [plain_decl, @ast.Stmt::Block([reg_decl, addr_stmt()], loc), addr_stmt()],
    loc,
  )
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(empty_prog([main_of(body)]))
  let hits = errs.filter(e => e.code == 3078)
  assert_eq(hits.length(), 1, msg="仅内层 register x 的取址报一次")
}

///|
/// #156：register 数组下标使用 → E3078（下标隐含退化 = 取址；clang 22 /
/// gcc 对 `register int a[3]; a[0] = 5;` 一律 error——退化语义实测）。
test "register_array_index_rejected" {
  let loc = @source.SourceLoc::new(2, 5)
  let reg_arr = @ast.Stmt::VarDecl(
    @ast.Type::Array(@ast.Type::int(), 3, [3], false, false, []),
    "a",
    None,
    [],
    false,
    true,
    loc,
  )
  let use_idx = @ast.Stmt::Expr(
    @ast.Expr::Index(
      @ast.Expr::Identifier("a", loc, @ast.Type::int()),
      @ast.Expr::Literal(0, loc, @ast.Type::int()),
      loc,
      @ast.Type::int(),
    ),
    loc,
  )
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(
    empty_prog([main_of(@ast.Stmt::Block([reg_arr, use_idx], loc))]),
  )
  assert_true(
    errs.exists(e => e.code == 3078),
    msg="register 数组下标应报 E3078",
  )
}

///|
/// #157：柔性数组成员聚合初始化 → E3079（C23 §6.7.2.1p23：含柔性数组
/// 成员的结构体该成员不可初始化；clang "initialization of flexible
/// array member" / gcc "non-static initialization of a flexible array
/// member"）。`struct Flex {int n; int d[];}` + `{2, {10,20}}` 报；
/// 仅初始化固定成员 `{2}` 合法零报。
fn flex_prog(init_elems : Array[@ast.InitElement]) -> @ast.ProgramNode {
  let loc = @source.SourceLoc::new(1, 1)
  let flex_struct : @ast.StructDecl = {
    loc,
    name: "Flex",
    fields: [
      { ty: @ast.Type::int(), name: "n", },
      {
        ty: @ast.Type::Array(@ast.Type::int(), -1, [-1], false, false, []),
        name: "d",
      },
    ],
    is_forward: false,
  }
  let f_decl = @ast.Stmt::VarDecl(
    @ast.Type::struct_type("Flex"),
    "f",
    Some(@ast.Expr::InitList(init_elems, loc, @ast.Type::void_type())),
    [],
    false,
    false,
    loc,
  )
  let prog = empty_prog([main_of(@ast.Stmt::Block([f_decl], loc))])
  prog.structs.push(flex_struct)
  prog
}

///|
test "flexible_array_member_init_rejected" {
  let loc = @source.SourceLoc::new(2, 5)
  let elems : Array[@ast.InitElement] = [
    { designators: [], value: @ast.Expr::Literal(2, loc, @ast.Type::int()), },
    {
      designators: [],
      value: @ast.Expr::InitList(
        [
          {
            designators: [],
            value: @ast.Expr::Literal(10, loc, @ast.Type::int()),
          },
          {
            designators: [],
            value: @ast.Expr::Literal(20, loc, @ast.Type::int()),
          },
        ],
        loc,
        @ast.Type::void_type(),
      ),
    },
  ]
  let tc = TypeChecker::new()
  let (prog, errs, _, _) = tc.check(flex_prog(elems))
  ignore(prog)
  assert_true(
    errs.exists(e => e.code == 3079),
    msg="柔性数组成员初始化应报 E3079",
  )
}

///|
/// #157 反向：仅初始化固定成员（柔性成员缺省）合法零报。
test "flexible_array_member_fixed_only_allowed" {
  let loc = @source.SourceLoc::new(2, 5)
  let elems : Array[@ast.InitElement] = [
    { designators: [], value: @ast.Expr::Literal(2, loc, @ast.Type::int()), },
  ]
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(flex_prog(elems))
  assert_false(
    errs.exists(e => e.code == 3079),
    msg="仅初始化固定成员不应报 E3079",
  )
}

///|
/// #157 定义面：柔性数组成员不在末位 → E3079（clang "flexible array
/// member is not at the end of struct"）。
test "flexible_member_not_last_rejected" {
  let loc = @source.SourceLoc::new(1, 1)
  let bad_struct : @ast.StructDecl = {
    loc,
    name: "Bad",
    fields: [
      {
        ty: @ast.Type::Array(@ast.Type::int(), -1, [-1], false, false, []),
        name: "d",
      },
      { ty: @ast.Type::int(), name: "n", },
    ],
    is_forward: false,
  }
  let prog = empty_prog([])
  prog.structs.push(bad_struct)
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(prog)
  assert_true(
    errs.exists(e => e.code == 3079),
    msg="柔性成员非末位应报 E3079",
  )
}
