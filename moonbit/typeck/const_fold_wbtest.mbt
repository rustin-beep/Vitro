///|
/// #142/#144/#150/#151 红锚批（2026-10-18 LLM 探针批四病）：
/// 文件作用域初始化器常量折叠（值锚）/ 重复 case E3074 / extern 再声明
/// 类型冲突 E3001 / 非常量初始化器 E3075（函数调用 + 变量引用两形态）。
/// J9：本批先证红后修——修复前五个断言全红。

///|
fn gdecl(
  ty : @ast.Type,
  name : String,
  init : @ast.Expr?,
  is_extern~ : Bool = false,
) -> @ast.GlobalDecl {
  {
    ..Default::default(),
    loc: @source.SourceLoc::new(1, 1),
    ty,
    name,
    init,
    is_extern,
    source_file: "t.c",
  }
}

///|
fn gprog(globals : Array[@ast.GlobalDecl]) -> @ast.ProgramNode {
  {
    structs: [],
    unions: [],
    globals,
    funcs: [],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
}

///|
/// #144：switch 重复 case 常量 → E3074（clang "duplicate case value"）。
test "dup_case_labels_rejected" {
  let loc = @source.SourceLoc::new(2, 5)
  fn case1(v : Int32) -> @ast.Stmt {
    @ast.Stmt::Case(
      Some(@ast.Expr::Literal(v, loc, @ast.Type::int())),
      @ast.Stmt::Expr(@ast.Expr::Literal(0, loc, @ast.Type::int()), loc),
      loc,
    )
  }
  let sw = @ast.Stmt::Switch(
    @ast.Expr::Literal(1, loc, @ast.Type::int()),
    @ast.Stmt::Block([case1(1), case1(1)], loc),
    loc,
  )
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(
    gprog([]) |> with_main(@ast.Stmt::Block([sw], loc)),
  )
  assert_true(
    errs.exists(e => e.code == 3074),
    msg="重复 case 常量应报 E3074",
  )
}

///|
/// #155：switch 多个 default 标签 → E3074（clang "multiple default labels
/// in one switch"）。判据基线 62f75d3d 在 #144 修复批（cbe7757b）之前，
/// 实测当前 HEAD 已拒——本锚锁行为防回归（cbe7757b 实现时 wbtest 只锚了
/// dup case 面，多 default 面零锚）。
test "multiple_default_labels_rejected" {
  let loc = @source.SourceLoc::new(2, 5)
  let sw = @ast.Stmt::Switch(
    @ast.Expr::Literal(1, loc, @ast.Type::int()),
    @ast.Stmt::Block(
      [
        @ast.Stmt::Case(
          None,
          @ast.Stmt::Return(
            Some(@ast.Expr::Literal(0, loc, @ast.Type::int())),
            loc,
          ),
          loc,
        ),
        @ast.Stmt::Case(
          None,
          @ast.Stmt::Return(
            Some(@ast.Expr::Literal(1, loc, @ast.Type::int())),
            loc,
          ),
          loc,
        ),
      ],
      loc,
    ),
    loc,
  )
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(
    gprog([]) |> with_main(@ast.Stmt::Block([sw], loc)),
  )
  assert_true(
    errs.exists(e => e.code == 3074),
    msg="多个 default 标签应报 E3074",
  )
}

///|
/// #150：extern 变量两次声明类型冲突 → E3001（clang "redeclaration of
/// 'shared' with a different type"）。
test "extern_redecl_type_conflict" {
  let p1 = gprog([
    gdecl(@ast.Type::int(), "shared", None, is_extern=true),
    gdecl(@ast.Type::double(), "shared", None, is_extern=true),
  ])
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(p1)
  assert_true(
    errs.exists(e => e.code == 3001),
    msg="extern 再声明类型冲突应报 E3001",
  )
  // 同型 extern 重声明合法不报（防误拒锚）
  let p2 = gprog([
    gdecl(@ast.Type::int(), "ok", None, is_extern=true),
    gdecl(@ast.Type::int(), "ok", None, is_extern=true),
  ])
  let tc2 = TypeChecker::new()
  let (_, errs2, _, _) = tc2.check(p2)
  assert_false(
    errs2.exists(e => e.code == 3001),
    msg="同型 extern 重声明不得误报",
  )
}

///|
/// #142 值锚：文件作用域 `int g = 3 + 5` 折叠为 Literal(8)。
test "global_const_expr_folded" {
  let loc = @source.SourceLoc::new(1, 1)
  let init = @ast.Expr::Binary(
    @ast.BinaryOp::Add,
    @ast.Expr::Literal(3, loc, @ast.Type::int()),
    @ast.Expr::Literal(5, loc, @ast.Type::int()),
    loc,
    @ast.Type::int(),
  )
  let (typed, errs, _, _) = {
    let tc = TypeChecker::new()
    tc.check(gprog([gdecl(@ast.Type::int(), "g", Some(init))]))
  }
  assert_eq(errs.length(), 0)
  match typed.globals[0].init {
    Some(@ast.Expr::Literal(v, _, _)) => assert_eq(v, 8)
    _ => fail("3+5 应折叠为 Literal(8)")
  }
}

///|
/// #151：`int g = f()` → E3075（函数调用非编译期常量；f 存根在册防
/// E3036 干扰）。
test "static_init_call_rejected" {
  let loc = @source.SourceLoc::new(1, 1)
  let init = @ast.Expr::Call("f", [], loc, @ast.Type::int())
  let f_stub : @ast.FuncDecl = {
    ..Default::default(),
    loc,
    return_type: @ast.Type::int(),
    name: "f",
    params: [],
    body: None,
    source_file: "t.c",
  }
  let prog : @ast.ProgramNode = {
    ..gprog([gdecl(@ast.Type::int(), "g", Some(init))]),
    funcs: [f_stub],
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(prog)
  assert_true(
    errs.exists(e => e.code == 3075),
    msg="函数调用初始化器应报 E3075",
  )
}

///|
/// #151：`int n = 5; int b = n + 1;` → E3075（变量引用非编译期常量；
/// clang "initializer element is not constant"）。
test "static_init_var_rejected" {
  let loc = @source.SourceLoc::new(1, 1)
  let five = @ast.Expr::Literal(5, loc, @ast.Type::int())
  let n_ref = @ast.Expr::Identifier("n", loc, @ast.Type::int())
  let b_init = @ast.Expr::Binary(
    @ast.BinaryOp::Add,
    n_ref,
    @ast.Expr::Literal(1, loc, @ast.Type::int()),
    loc,
    @ast.Type::int(),
  )
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(
    gprog([
      gdecl(@ast.Type::int(), "n", Some(five)),
      gdecl(@ast.Type::int(), "b", Some(b_init)),
    ]),
  )
  assert_true(
    errs.exists(e => e.code == 3075),
    msg="变量引用初始化器应报 E3075",
  )
}

///|
/// with_main：globals 程序挂 main 包装（dup case 用例的载体）。
fn with_main(prog : @ast.ProgramNode, body : @ast.Stmt) -> @ast.ProgramNode {
  let loc = @source.SourceLoc::new(1, 1)
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc,
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(body),
    source_file: "t.c",
  }
  { ..prog, funcs: [main], }
}

///|
/// #145：不完整 struct 使用双面——前向声明后声明变量报 E3076（旧形态
/// 零诊断放行）；前向+完整定义合法升级（旧形态误报 E3002 重复定义）。
test "incomplete_type_two_sides" {
  let loc = @source.SourceLoc::new(1, 1)
  fn fwd_decl(name : String) -> @ast.StructDecl {
    { loc, name, fields: [], is_forward: true, }
  }
  // 面 1：`struct S;` 后声明 `struct S s;` → E3076
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(
    with_main(
      gprog([]),
      @ast.Stmt::VarDecl(
        @ast.Type::struct_type("S"),
        "s",
        None,
        [],
        false,
        false,
        loc,
      ),
    )
    |> prog_with_structs([fwd_decl("S")]),
  )
  assert_true(
    errs.exists(e => e.code == 3076),
    msg="前向声明后声明变量应报 E3076",
  )
  // 面 2：前向 + 完整定义 → 零 E3002（合法升级）+ 零 E3076
  let full : @ast.StructDecl = {
    loc,
    name: "N",
    fields: [{ ty: @ast.Type::int(), name: "v", }],
    is_forward: false,
  }
  let tc2 = TypeChecker::new()
  let (_, errs2, _, _) = tc2.check(
    with_main(
      gprog([]),
      @ast.Stmt::VarDecl(
        @ast.Type::struct_type("N"),
        "n",
        None,
        [],
        false,
        false,
        loc,
      ),
    )
    |> prog_with_structs([fwd_decl("N"), full]),
  )
  assert_false(
    errs2.exists(e => e.code == 3002 || e.code == 3076),
    msg="前向+完整定义合法：不得报 E3002/E3076",
  )
}

///|
/// with_main 的 structs 注入伴件（with_main 之后链式调用）。
fn prog_with_structs(
  prog : @ast.ProgramNode,
  structs : Array[@ast.StructDecl],
) -> @ast.ProgramNode {
  { ..prog, structs, }
}

///|
/// 对抗批红锚（2026-10-18）：①完整后再前向声明不反向覆盖（codegen
/// struct_defs 错位根因的 typeck 侧净化）；②函数定义签名三面
/// （参数/返回值）不完整报 E3076；③成员面不完整报 E3076——均
/// clang 对齐（adv_g 形态收编）。
test "fwd_after_complete_and_sig_faces" {
  let loc = @source.SourceLoc::new(1, 1)
  // ①净化：完整定义 + 后续前向 → 前向条目出列（structs 数组只剩完整）
  let full : @ast.StructDecl = {
    loc,
    name: "S",
    fields: [{ ty: @ast.Type::int(), name: "a", }],
    is_forward: false,
  }
  let fwd : @ast.StructDecl = { loc, name: "S", fields: [], is_forward: true, }
  let tc = TypeChecker::new()
  let (typed, _, _, _) = tc.check({
    structs: [full, fwd],
    unions: [],
    globals: [],
    funcs: [],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_eq(
    typed.structs.length(),
    1,
    msg="完整后再前向：前向条目应净化出列",
  )
  assert_false(typed.structs[0].is_forward)
  // ②③签名三面 + 成员面：前向 Incomplete 的参数/返回值/值成员 → E3076
  let inc_fwd : @ast.StructDecl = {
    loc,
    name: "Inc",
    fields: [],
    is_forward: true,
  }
  let holder : @ast.StructDecl = {
    loc,
    name: "Holder",
    fields: [{ ty: @ast.Type::struct_type("Inc"), name: "m", }],
    is_forward: false,
  }
  let fn_sig : @ast.FuncDecl = {
    ..Default::default(),
    loc,
    return_type: @ast.Type::struct_type("Inc"),
    name: "ret_inc",
    params: [
      { ty: @ast.Type::struct_type("Inc"), name: "s", loc, default: None, },
    ],
    body: Some(@ast.Stmt::Block([], loc)),
    source_file: "t.c",
  }
  let tc2 = TypeChecker::new()
  let (_, errs, _, _) = tc2.check({
    structs: [inc_fwd, holder],
    unions: [],
    globals: [],
    funcs: [fn_sig],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  // 参数面 + 返回值面 + 成员面 = 三处 E3076
  assert_eq(
    errs.filter(e => e.code == 3076).length(),
    3,
    msg="参数/返回值/成员三面各报一处 E3076",
  )
}

///|
/// P1-2（2026-10-18 审阅批）：常量折叠的符号性对偶——CVal 纯值域无符号
/// 位，比较/除法全走 Int64 有符号域、CE_Cast 整型恒等丢 unsigned。
/// 三形态锚（clang 22.1.4 实测 1/1/0）：`(0u-1u)>0`（u32 回绕巨值为真）、
/// `(unsigned)-1>0`（cast 无符号域为真）、`-1<1u`（usual conversions 升
/// 无符号域，-1 位模式巨值不小于 1u → 假）。
test "const_fold_unsigned_semantics" {
  let loc = @source.SourceLoc::new(1, 1)
  fn uint_lit(v : Int32) -> @ast.Expr {
    @ast.Expr::Literal(v, loc, @ast.Type::unsigned_int())
  }
  fn int_lit(v : Int32) -> @ast.Expr {
    @ast.Expr::Literal(v, loc, @ast.Type::int())
  }
  fn neg_int(v : Int32) -> @ast.Expr {
    @ast.Expr::Unary(@ast.UnaryOp::Neg, int_lit(v), loc, @ast.Type::int())
  }
  // a = (0u - 1u) > 0  —— clang: 1
  let expr_a : @ast.Expr = @ast.Expr::Binary(
    @ast.BinaryOp::Gt,
    @ast.Expr::Binary(
      @ast.BinaryOp::Sub,
      uint_lit(0),
      uint_lit(1),
      loc,
      @ast.Type::unsigned_int(),
    ),
    int_lit(0),
    loc,
    @ast.Type::int(),
  )
  // b = (unsigned)-1 > 0  —— clang: 1
  let expr_b : @ast.Expr = @ast.Expr::Binary(
    @ast.BinaryOp::Gt,
    @ast.Expr::Cast(
      neg_int(1),
      @ast.Type::unsigned_int(),
      loc,
      @ast.Type::unsigned_int(),
    ),
    int_lit(0),
    loc,
    @ast.Type::int(),
  )
  // c = -1 < 1u  —— clang: 0
  let expr_c : @ast.Expr = @ast.Expr::Binary(
    @ast.BinaryOp::Lt,
    neg_int(1),
    uint_lit(1),
    loc,
    @ast.Type::int(),
  )
  let tc = TypeChecker::new()
  let (typed, errs, _, _) = tc.check(
    gprog([
      gdecl(@ast.Type::int(), "a", Some(expr_a)),
      gdecl(@ast.Type::int(), "b", Some(expr_b)),
      gdecl(@ast.Type::int(), "c", Some(expr_c)),
    ]),
  )
  assert_eq(errs.length(), 0, msg="三形态均合法常量表达式")
  fn folded_v(g : @ast.GlobalDecl, want : String) -> Unit raise {
    match g.init {
      Some(@ast.Expr::Literal(v, _, _)) =>
        assert_eq(v, if want == "a" { 1 } else if want == "b" { 1 } else { 0 })
      _ => fail("\{want} 应折叠为 Literal（clang 值 1/1/0）")
    }
  }
  folded_v(typed.globals[0], "a")
  folded_v(typed.globals[1], "b")
  folded_v(typed.globals[2], "c")
}

///|
/// #183（2026-10-18 深挖批）：标量初始化器的大括号包裹（C11 6.7.9p11）
/// ——`int x = {5}` ≡ 5、多余元素 W3005 取首。四收口面（全局/局部/
/// 标量字段/数组标量元素）断言零 E3004/E3006 + 定型正确（聚合目标的
/// InitList 不受解包扰动）。
test "scalar_brace_unwrap_four_sites" {
  let loc = @source.SourceLoc::new(1, 1)
  // 全局：int g = {42}（≡ 42）；int g2 = {7,8}（excess 取首 7）
  let g_decl = gdecl(
    @ast.Type::int(),
    "g",
    Some(
      @ast.Expr::InitList(
        [
          {
            designators: [],
            value: @ast.Expr::Literal(42, loc, @ast.Type::int()),
          },
        ],
        loc,
        @ast.Type::void_type(),
      ),
    ),
  )
  let g2_decl = gdecl(
    @ast.Type::int(),
    "g2",
    Some(
      @ast.Expr::InitList(
        [
          {
            designators: [],
            value: @ast.Expr::Literal(7, loc, @ast.Type::int()),
          },
          {
            designators: [],
            value: @ast.Expr::Literal(8, loc, @ast.Type::int()),
          },
        ],
        loc,
        @ast.Type::void_type(),
      ),
    ),
  )
  // main：int x = {5};（局部）+ int a[2] = {{1},2};（数组标量元素）
  let x_decl : @ast.Stmt = @ast.Stmt::VarDecl(
    @ast.Type::int(),
    "x",
    Some(
      @ast.Expr::InitList(
        [
          {
            designators: [],
            value: @ast.Expr::Literal(5, loc, @ast.Type::int()),
          },
        ],
        loc,
        @ast.Type::void_type(),
      ),
    ),
    [],
    false,
    false,
    loc,
  )
  let a_decl : @ast.Stmt = @ast.Stmt::VarDecl(
    @ast.Type::array_of(@ast.Type::int(), [2]),
    "a",
    Some(
      @ast.Expr::InitList(
        [
          {
            designators: [],
            value: @ast.Expr::InitList(
              [
                {
                  designators: [],
                  value: @ast.Expr::Literal(1, loc, @ast.Type::int()),
                },
              ],
              loc,
              @ast.Type::void_type(),
            ),
          },
          {
            designators: [],
            value: @ast.Expr::Literal(2, loc, @ast.Type::int()),
          },
        ],
        loc,
        @ast.Type::void_type(),
      ),
    ),
    [],
    false,
    false,
    loc,
  )
  let ret = @ast.Stmt::Return(
    Some(@ast.Expr::Identifier("x", loc, @ast.Type::int())),
    loc,
  )
  let tc = TypeChecker::new()
  let (typed, errs, warns, _) = tc.check(
    gprog([g_decl, g2_decl])
    |> with_main(@ast.Stmt::Block([x_decl, a_decl, ret], loc)),
  )
  // 四面零 error（旧：E3004×2 全局 + E3004 局部 + E3006 数组元素）
  assert_eq(errs.length(), 0, msg="括号包裹四面零误拒（#183）")
  // excess 一条 W3005（g2 的 {7,8}）
  assert_eq(warns.filter(w => w.code == 3005).length(), 1)
  // 全局折值：g ≡ 42
  match typed.globals[0].init {
    Some(@ast.Expr::Literal(v, _, _)) => assert_eq(v, 42)
    _ => fail("g={42} 应解包折叠为 Literal(42)")
  }
}

///|
/// #264（2026-10-22）：静态初始化器的数组名地址常量放行——C23 §6.6p9
/// 数组右值退化指向首元素（静态存储期对象）＝地址常量，静态规格表
/// 互引用合法形态；标量变量引用照旧报 E3075（负锚防误放）。
test "issue264_static_init_array_name_allowed" {
  let loc = @source.SourceLoc::new(3, 22)
  // static const char X[] = "hello";  static const S s = { X };
  let x_decl : @ast.GlobalDecl = {
    ..Default::default(),
    loc: @source.SourceLoc::new(2, 1),
    ty: @ast.Type::Array(@ast.Type::char(), 6, [6], true, false, []),
    name: "X",
    init: Some(
      @ast.Expr::StringLiteral(
        "hello",
        @source.SourceLoc::new(2, 27),
        @ast.Type::char(),
      ),
    ),
    source_file: "t.c",
  }
  let s_decl : @ast.GlobalDecl = {
    ..Default::default(),
    loc,
    ty: @ast.Type::Struct("S", false),
    name: "s",
    init: Some(
      @ast.Expr::InitList(
        [
          {
            designators: [],
            value: @ast.Expr::Identifier("X", loc, @ast.Type::char()),
          },
        ],
        loc,
        @ast.Type::Struct("S", false),
      ),
    ),
    source_file: "t.c",
  }
  let tc = TypeChecker::new()
  // struct S { const char *p; } 需登记——直接走 structs 声明省略，改用
  // 标量形态压最小面：static const char *pick = X;（数组名初始化指针）
  let pick_decl : @ast.GlobalDecl = {
    ..Default::default(),
    loc,
    ty: @ast.Type::pointer_to(@ast.Type::char()),
    name: "pick",
    init: Some(@ast.Expr::Identifier("X", loc, @ast.Type::char())),
    source_file: "t.c",
  }
  let (_, errs, _, _) = tc.check(gprog([x_decl, pick_decl, s_decl]))
  // s 的 struct 未登记会有 E3076 类噪声——只断言 E3075 零命中（核心面）
  assert_false(
    errs.exists(e => e.code == 3075),
    msg="数组名是地址常量，静态初始化器不得报 E3075",
  )
}

///|
/// #264 负锚：标量变量引用照旧报（防放行面过宽）。
test "issue264_scalar_var_ref_still_e3075" {
  let loc = @source.SourceLoc::new(2, 20)
  let n_decl : @ast.GlobalDecl = {
    ..Default::default(),
    loc: @source.SourceLoc::new(1, 1),
    ty: @ast.Type::int(),
    name: "n",
    init: Some(@ast.Expr::Literal(5, loc, @ast.Type::int())),
    source_file: "t.c",
  }
  let b_decl : @ast.GlobalDecl = {
    ..Default::default(),
    loc,
    ty: @ast.Type::int(),
    name: "b",
    init: Some(
      @ast.Expr::Binary(
        @ast.BinaryOp::Add,
        @ast.Expr::Identifier("n", loc, @ast.Type::int()),
        @ast.Expr::Literal(1, loc, @ast.Type::int()),
        loc,
        @ast.Type::int(),
      ),
    ),
    source_file: "t.c",
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(gprog([n_decl, b_decl]))
  assert_true(
    errs.exists(e => e.code == 3075),
    msg="标量变量引用静态初始化器应照旧报 E3075",
  )
}

///|
/// #265（2026-10-22）：cast 维数误判 VLA 的常量二次折叠——`(int)(2+1)`
/// 维度经 refold_vla_const_dims 回填定长 [3,40]，check 管线零 error。
test "issue265_refold_cast_dims" {
  let tc = TypeChecker::new()
  // dims=[0,40] 0 哨兵 + vla_dims=[Cast(Literal 3)]——parser 折不出形态
  let cast3 : @ast.Expr = @ast.Expr::Cast(
    @ast.Expr::Literal(3, @source.SourceLoc::new(5, 19), @ast.Type::int()),
    @ast.Type::int(),
    @source.SourceLoc::new(5, 14),
    @ast.Type::int(),
  )
  let vla_ty = @ast.Type::Array(@ast.Type::char(), 0, [0, 40], false, true, [
    cast3,
  ])
  match tc.refold_vla_const_dims(vla_ty) {
    Array(_, size, dims, _, is_vla, vd) => {
      inspect(size, content="120")
      inspect(dims[0], content="3")
      inspect(dims[1], content="40")
      inspect(is_vla, content="false")
      inspect(vd.length(), content="0")
    }
    _ => fail("refold 产物应为数组")
  }
  // 负锚：真 VLA（Identifier 维度）折不回、维持原样
  let n_dim : @ast.Expr = @ast.Expr::Identifier(
    "n",
    @source.SourceLoc::new(5, 19),
    @ast.Type::int(),
  )
  let true_vla = @ast.Type::Array(@ast.Type::char(), 0, [0, 40], false, true, [
    n_dim,
  ])
  match tc.refold_vla_const_dims(true_vla) {
    Array(_, _, _, _, is_vla, vd) => {
      inspect(is_vla, content="true")
      inspect(vd.length(), content="1")
    }
    _ => fail("真 VLA 应原样返回")
  }
}
