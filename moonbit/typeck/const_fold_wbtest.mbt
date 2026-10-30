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

///|
/// #266/#249（2026-10-22，C11 6.7.2.1p13）：匿名成员提升的三面锚——
/// designated 查名穿透（.a 命中匿名 union 内部）、位置初始化透传
/// （标量包 InitList 递归匿名成员）、双匿名不撞重名（空名跳过）。
test "issue266_anon_member_promotion" {
  let loc = @source.SourceLoc::new(3, 22)
  // struct AnonUnion { union { int a; float b; }; };
  let anon_union_ty = @ast.Type::Union("__anon_u", false)
  let s_decl : @ast.StructDecl = {
    ..Default::default(),
    loc: @source.SourceLoc::new(1, 1),
    name: "AnonUnion",
    fields: [{ ty: anon_union_ty, name: "", }],
    is_forward: false,
  }
  let x_decl : @ast.GlobalDecl = {
    ..Default::default(),
    loc,
    ty: @ast.Type::Struct("AnonUnion", false),
    name: "g",
    init: Some(
      @ast.Expr::InitList(
        [
          {
            designators: [@ast.Designator::Field("a")],
            value: @ast.Expr::Literal(2, loc, @ast.Type::int()),
          },
        ],
        loc,
        @ast.Type::Struct("AnonUnion", false),
      ),
    ),
    source_file: "t.c",
  }
  let tc = TypeChecker::new()
  let (typed, errs, _, _) = tc.check({
    structs: [s_decl],
    unions: [
      {
        ..Default::default(),
        loc: @source.SourceLoc::new(2, 3),
        name: "__anon_u",
        fields: [
          { ty: @ast.Type::int(), name: "a", },
          { ty: @ast.Type::float(), name: "b", },
        ],
        is_forward: false,
      },
    ],
    globals: [x_decl],
    funcs: [],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  // designated .a 穿透命中：零 E3042/E3006
  assert_false(
    errs.exists(e => e.code == 3042 || e.code == 3006),
    msg="匿名成员 designated 应穿透命中不误拒",
  )
  // 静态折叠面：值折成 Literal(2)（find_field_ty 穿透）
  ignore(typed)
}

///|
/// #249 负锚锚：双匿名成员（两个空名）不互撞 E3080。
test "issue249_double_anon_no_dup" {
  let s_decl : @ast.StructDecl = {
    ..Default::default(),
    loc: @source.SourceLoc::new(1, 1),
    name: "Mixed",
    fields: [
      { ty: @ast.Type::Union("__u1", false), name: "", },
      { ty: @ast.Type::Union("__u2", false), name: "", },
    ],
    is_forward: false,
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check({
    structs: [s_decl],
    unions: [],
    globals: [],
    funcs: [],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_false(
    errs.exists(e => e.code == 3080),
    msg="双匿名成员（空名）不参与重名判——C11 6.7.2.1p13",
  )
}

///|
/// #331（2026-10-27）：文件作用域初始化器**前向引用**守卫——C11 6.2.1p4
/// 声明点语义（标识符自声明符完成才可见），clang 对 `int *p = &s; int s;`
/// 报 use of undeclared identifier。typeck Pass 2.5 两段式（先全登记再查
/// 初始化器）破坏序语义，地址常量族（&s / 数组名 / &s.x 链）经 codegen
/// pending 回填被静默接受。守卫按 globals 数组序（= 声明点序）判前向。
test "issue331_fwd_addr_init_rejected" {
  let loc = @source.SourceLoc::new(1, 11)
  // int *p = &s;  int s;
  let p_decl = gdecl(
    @ast.Type::pointer_to(@ast.Type::int()),
    "p",
    Some(
      @ast.Expr::Unary(
        @ast.UnaryOp::Addr,
        @ast.Expr::Identifier("s", loc, @ast.Type::int()),
        loc,
        @ast.Type::pointer_to(@ast.Type::int()),
      ),
    ),
  )
  let s_decl = gdecl(@ast.Type::int(), "s", None)
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(gprog([p_decl, s_decl]))
  assert_true(
    errs.exists(e => e.code == 3023),
    msg="前向引用 &s 应报 E3023（声明点在其后）",
  )
}

///|
/// #331：数组名地址常量的前向引用同族——`int *p = arr; int arr[3];`。
test "issue331_fwd_array_name_rejected" {
  let loc = @source.SourceLoc::new(1, 11)
  let p_decl = gdecl(
    @ast.Type::pointer_to(@ast.Type::int()),
    "p",
    Some(@ast.Expr::Identifier("arr", loc, @ast.Type::int())),
  )
  let arr_decl = gdecl(
    @ast.Type::Array(@ast.Type::int(), 3, [3], false, false, []),
    "arr",
    None,
  )
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(gprog([p_decl, arr_decl]))
  assert_true(
    errs.exists(e => e.code == 3023),
    msg="前向引用数组名 arr 应报 E3023",
  )
}

///|
/// #331：地址常量链形态前向引用——`int *p = &st.x; struct S st;` 的 base
/// 前向（st 声明在后）。struct 类型面登记在 structs（无噪声），base 变量
/// 序在 init 之后。
test "issue331_fwd_chain_base_rejected" {
  let loc = @source.SourceLoc::new(1, 11)
  let s_ty = @ast.Type::Struct("S", false)
  let p_decl = gdecl(
    @ast.Type::pointer_to(@ast.Type::int()),
    "p",
    Some(
      @ast.Expr::Unary(
        @ast.UnaryOp::Addr,
        @ast.Expr::Member(
          @ast.Expr::Identifier("st", loc, s_ty),
          "x",
          false,
          loc,
          @ast.Type::int(),
        ),
        loc,
        @ast.Type::pointer_to(@ast.Type::int()),
      ),
    ),
  )
  let st_decl = gdecl(s_ty, "st", None)
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(gprog([p_decl, st_decl]))
  assert_true(
    errs.exists(e => e.code == 3023),
    msg="前向引用链 base st 应报 E3023",
  )
}

///|
/// #331 负锚：顺序合法（声明在前）的 &s 零 E3023——防守卫误拒正常程序。
test "issue331_backref_addr_allowed" {
  let loc = @source.SourceLoc::new(2, 11)
  let s_decl = gdecl(@ast.Type::int(), "s", None)
  let p_decl = gdecl(
    @ast.Type::pointer_to(@ast.Type::int()),
    "p",
    Some(
      @ast.Expr::Unary(
        @ast.UnaryOp::Addr,
        @ast.Expr::Identifier("s", loc, @ast.Type::int()),
        loc,
        @ast.Type::pointer_to(@ast.Type::int()),
      ),
    ),
  )
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(gprog([s_decl, p_decl]))
  assert_false(
    errs.exists(e => e.code == 3023),
    msg="后向引用 &s（s 先行声明）不得误报",
  )
}

///|
/// #331 负锚：extern 先行声明（定义在后）合法——`extern int e; int *p = &e;
/// int e = 7;`（codegen pending 回填的活通道，见 #331 销案评论）。
test "issue331_extern_predecl_allowed" {
  let loc = @source.SourceLoc::new(2, 11)
  let e_extern = gdecl(@ast.Type::int(), "e", None, is_extern=true)
  let p_decl = gdecl(
    @ast.Type::pointer_to(@ast.Type::int()),
    "p",
    Some(
      @ast.Expr::Unary(
        @ast.UnaryOp::Addr,
        @ast.Expr::Identifier("e", loc, @ast.Type::int()),
        loc,
        @ast.Type::pointer_to(@ast.Type::int()),
      ),
    ),
  )
  let e_def = gdecl(
    @ast.Type::int(),
    "e",
    Some(@ast.Expr::Literal(7, loc, @ast.Type::int())),
  )
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(gprog([e_extern, p_decl, e_def]))
  assert_false(
    errs.exists(e => e.code == 3023),
    msg="extern 先行声明 + 定义在后是合法形态，不得误报",
  )
}

///|
/// PR #339 审阅 P3-2（2026-10-27）：`&arr[j]` 的**索引子表达式**前向引用
/// ——j 声明在初始化器之后，clang 报 use of undeclared；守卫此前只沿
/// 链脊（Member/Index 的 obj/arr 侧）取 base，索引位漏检。
test "issue331_fwd_index_expr_rejected" {
  let loc = @source.SourceLoc::new(1, 26)
  let arr_decl = gdecl(
    @ast.Type::Array(@ast.Type::int(), 4, [4], false, false, []),
    "arr",
    None,
  )
  let p_decl = gdecl(
    @ast.Type::pointer_to(@ast.Type::int()),
    "p",
    Some(
      @ast.Expr::Unary(
        @ast.UnaryOp::Addr,
        @ast.Expr::Index(
          @ast.Expr::Identifier("arr", loc, @ast.Type::int()),
          @ast.Expr::Identifier("j", loc, @ast.Type::int()),
          loc,
          @ast.Type::int(),
        ),
        loc,
        @ast.Type::pointer_to(@ast.Type::int()),
      ),
    ),
  )
  let j_decl = gdecl(@ast.Type::int(), "j", None)
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(gprog([arr_decl, p_decl, j_decl]))
  assert_true(
    errs.exists(e => e.code == 3023),
    msg="索引子表达式前向引用 j 应报 E3023（PR #339 审阅 P3-2）",
  )
}

///|
/// PR #339 审阅 P3-2 负锚：索引位先行声明（j 在前）零误报。
test "issue331_fwd_index_expr_backref_allowed" {
  let loc = @source.SourceLoc::new(2, 26)
  let j_decl = gdecl(
    @ast.Type::int(),
    "j",
    Some(@ast.Expr::Literal(1, loc, @ast.Type::int())),
  )
  let arr_decl = gdecl(
    @ast.Type::Array(@ast.Type::int(), 4, [4], false, false, []),
    "arr",
    None,
  )
  let p_decl = gdecl(
    @ast.Type::pointer_to(@ast.Type::int()),
    "p",
    Some(
      @ast.Expr::Unary(
        @ast.UnaryOp::Addr,
        @ast.Expr::Index(
          @ast.Expr::Identifier("arr", loc, @ast.Type::int()),
          @ast.Expr::Identifier("j", loc, @ast.Type::int()),
          loc,
          @ast.Type::int(),
        ),
        loc,
        @ast.Type::pointer_to(@ast.Type::int()),
      ),
    ),
  )
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(gprog([j_decl, arr_decl, p_decl]))
  assert_false(
    errs.exists(e => e.code == 3023),
    msg="索引位先行声明不得误报（PR #339 审阅 P3-2）",
  )
}

// ============================================================================
// #337（2026-10-28）：函数体前向引用守卫——#331 同病根的函数体/作值面。
// J9：本批先证红后修（issue337_fwd_* 四锚修复前全红，负例六锚防误拒）。
// ============================================================================

///|
/// #337 主体：函数体前向引用后文全局——C11 6.2.1p4 声明点语义，clang 对
/// `int main(void){ return s; } int s = 3;` 报 use of undeclared
/// identifier 's'。Pass 2.5 全量登记后函数体 lookup_var 直接命中已登记
/// 符号（#331 只收了初始化器地址常量族窄口——diagnose_static_init）。
test "issue337_fwd_funcbody_global_rejected" {
  let loc = @source.SourceLoc::new(1, 27)
  let s_decl = {
    ..gdecl(
      @ast.Type::int(),
      "s",
      Some(@ast.Expr::Literal(3, loc, @ast.Type::int())),
    ),
    loc: @source.SourceLoc::new(2, 1),
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(
    with_main(
      gprog([s_decl]),
      @ast.Stmt::Return(
        Some(@ast.Expr::Identifier("s", loc, @ast.Type::int())),
        loc,
      ),
    ),
  )
  assert_true(
    errs.exists(e => e.code == 3023),
    msg="函数体前向引用后文全局 s 应报 E3023（#337 主体）",
  )
}

///|
/// #337（PR #339 审阅 P3-2 挂账）：初始化器**函数名作值**前向引用——
/// `int (*fp)(void) = f; int f(void){...}`，clang 报 use of undeclared
/// identifier 'f'。funcs 表 Pass 2 全量登记（早于 Pass 2.5），函数名
/// 无声明序信息（const_eval.mbt 索引守卫注释明写「函数名前向挂 #337」）。
test "issue337_fwd_funcname_addr_init_rejected" {
  let loc = @source.SourceLoc::new(1, 22)
  let fp_decl = gdecl(
    @ast.Type::function_pointer(@ast.Type::int(), []),
    "fp",
    Some(@ast.Expr::Identifier("f", loc, @ast.Type::int())),
  )
  let f_def : @ast.FuncDecl = {
    ..Default::default(),
    loc: @source.SourceLoc::new(2, 1),
    return_type: @ast.Type::int(),
    name: "f",
    params: [],
    body: Some(
      @ast.Stmt::Return(Some(@ast.Expr::Literal(0, loc, @ast.Type::int())), loc),
    ),
    source_file: "t.c",
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check({ ..gprog([fp_decl]), funcs: [f_def], })
  assert_true(
    errs.exists(e => e.code == 3023),
    msg="初始化器函数名作值前向引用 f 应报 E3023（P3-2 挂账销案）",
  )
}

///|
/// #337：函数体内**函数名作值**前向引用同族——
/// `int main(void){ int (*fp)(void) = f; ... } int f(void){...}`。
test "issue337_fwd_funcname_addr_funcbody_rejected" {
  let loc = @source.SourceLoc::new(1, 30)
  let f_def : @ast.FuncDecl = {
    ..Default::default(),
    loc: @source.SourceLoc::new(2, 1),
    return_type: @ast.Type::int(),
    name: "f",
    params: [],
    body: Some(
      @ast.Stmt::Return(Some(@ast.Expr::Literal(0, loc, @ast.Type::int())), loc),
    ),
    source_file: "t.c",
  }
  let tc = TypeChecker::new()
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc: @source.SourceLoc::new(1, 1),
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(
      @ast.Stmt::Block(
        [
          @ast.Stmt::VarDecl(
            @ast.Type::function_pointer(@ast.Type::int(), []),
            "fp",
            Some(@ast.Expr::Identifier("f", loc, @ast.Type::int())),
            [],
            false,
            false,
            loc,
          ),
          @ast.Stmt::Return(
            Some(@ast.Expr::Literal(0, loc, @ast.Type::int())),
            loc,
          ),
        ],
        loc,
      ),
    ),
    source_file: "t.c",
  }
  let (_, errs, _, _) = tc.check({ ..gprog([]), funcs: [main, f_def], })
  assert_true(
    errs.exists(e => e.code == 3023),
    msg="函数体内函数名作值前向引用 f 应报 E3023",
  )
}

///|
/// #337：static 函数名作值前向引用连坐——作值面无隐式声明回退（调用
/// 面 E3058 前向序在 check_user_func，值使用侧此前零守卫——#5 销案的
/// 「值使用侧不重复」指跨文件可见性维度，前向序是新增维度不违背）。
test "issue337_fwd_static_funcname_addr_rejected" {
  let loc = @source.SourceLoc::new(1, 30)
  let h_def : @ast.FuncDecl = {
    ..Default::default(),
    loc: @source.SourceLoc::new(2, 1),
    return_type: @ast.Type::int(),
    name: "h",
    params: [],
    body: Some(
      @ast.Stmt::Return(Some(@ast.Expr::Literal(0, loc, @ast.Type::int())), loc),
    ),
    is_static: true,
    source_file: "t.c",
  }
  let tc = TypeChecker::new()
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc: @source.SourceLoc::new(1, 1),
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(
      @ast.Stmt::Block(
        [
          @ast.Stmt::VarDecl(
            @ast.Type::function_pointer(@ast.Type::int(), []),
            "fp",
            Some(@ast.Expr::Identifier("h", loc, @ast.Type::int())),
            [],
            false,
            false,
            loc,
          ),
          @ast.Stmt::Return(
            Some(@ast.Expr::Literal(0, loc, @ast.Type::int())),
            loc,
          ),
        ],
        loc,
      ),
    ),
    source_file: "t.c",
  }
  let (_, errs, _, _) = tc.check({ ..gprog([]), funcs: [main, h_def], })
  assert_true(
    errs.exists(e => e.code == 3023),
    msg="static 函数名作值前向引用 h 应报 E3023（连坐面）",
  )
}

///|
/// #337 负锚：全局先行声明 + 函数体后文引用——正常程序零误报。
test "issue337_backref_global_allowed" {
  let loc = @source.SourceLoc::new(2, 27)
  let s_decl = gdecl(
    @ast.Type::int(),
    "s",
    Some(@ast.Expr::Literal(3, @source.SourceLoc::new(1, 10), @ast.Type::int())),
  )
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc: @source.SourceLoc::new(2, 1),
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(
      @ast.Stmt::Return(
        Some(@ast.Expr::Identifier("s", loc, @ast.Type::int())),
        loc,
      ),
    ),
    source_file: "t.c",
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check({ ..gprog([s_decl]), funcs: [main], })
  assert_false(
    errs.exists(e => e.code == 3023),
    msg="后文引用先行全局 s 不得误报",
  )
}

///|
/// #337 负锚：extern 先行声明（定义在后）+ 函数体引用——合法形态
///（首声明行取 extern 条目，#331 的 global_first_decl_idx 首值模式同款）。
test "issue337_extern_predecl_funcbody_allowed" {
  let loc = @source.SourceLoc::new(2, 27)
  let e_extern = gdecl(@ast.Type::int(), "e", None, is_extern=true)
  let e_def = {
    ..gdecl(
      @ast.Type::int(),
      "e",
      Some(
        @ast.Expr::Literal(7, @source.SourceLoc::new(3, 10), @ast.Type::int()),
      ),
    ),
    loc: @source.SourceLoc::new(3, 1),
  }
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc: @source.SourceLoc::new(2, 1),
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(
      @ast.Stmt::Return(
        Some(@ast.Expr::Identifier("e", loc, @ast.Type::int())),
        loc,
      ),
    ),
    source_file: "t.c",
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check({ ..gprog([e_extern, e_def]), funcs: [main], })
  assert_false(
    errs.exists(e => e.code == 3023),
    msg="extern 先行声明 + 函数体引用是合法形态，不得误报",
  )
}

///|
/// #337 负锚：tentative 先行（`int s; ... int s = 3;`）+ 函数体引用
/// ——首声明行取 tentative 条目（C11 §6.9.2）。
test "issue337_tentative_predecl_funcbody_allowed" {
  let loc = @source.SourceLoc::new(2, 27)
  let s_tent = gdecl(@ast.Type::int(), "s", None)
  let s_def = {
    ..gdecl(
      @ast.Type::int(),
      "s",
      Some(
        @ast.Expr::Literal(3, @source.SourceLoc::new(3, 10), @ast.Type::int()),
      ),
    ),
    loc: @source.SourceLoc::new(3, 1),
  }
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc: @source.SourceLoc::new(2, 1),
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(
      @ast.Stmt::Return(
        Some(@ast.Expr::Identifier("s", loc, @ast.Type::int())),
        loc,
      ),
    ),
    source_file: "t.c",
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check({ ..gprog([s_tent, s_def]), funcs: [main], })
  assert_false(
    errs.exists(e => e.code == 3023),
    msg="tentative 先行声明 + 函数体引用是合法形态，不得误报",
  )
}

///|
/// #337 负锚：函数原型先行 + 函数名作值——`int f(void); int (*fp)(void)
/// = f; int f(void){...}`（first_decl_line 取原型条目，Pass 2 首值语义）。
test "issue337_prototype_predecl_addr_allowed" {
  let loc = @source.SourceLoc::new(2, 22)
  let proto : @ast.FuncDecl = {
    ..Default::default(),
    loc: @source.SourceLoc::new(1, 1),
    return_type: @ast.Type::int(),
    name: "f",
    params: [],
    body: None,
    source_file: "t.c",
  }
  let f_def : @ast.FuncDecl = {
    ..Default::default(),
    loc: @source.SourceLoc::new(3, 1),
    return_type: @ast.Type::int(),
    name: "f",
    params: [],
    body: Some(
      @ast.Stmt::Return(Some(@ast.Expr::Literal(0, loc, @ast.Type::int())), loc),
    ),
    source_file: "t.c",
  }
  let fp_decl = gdecl(
    @ast.Type::function_pointer(@ast.Type::int(), []),
    "fp",
    Some(@ast.Expr::Identifier("f", loc, @ast.Type::int())),
  )
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check({ ..gprog([fp_decl]), funcs: [proto, f_def], })
  assert_false(
    errs.exists(e => e.code == 3023),
    msg="原型先行 + 函数名作值是合法形态，不得误报",
  )
}

///|
/// #337 负锚：局部遮蔽——函数体内声明同名局部后引用命中 scope 栈内层，
/// 不进全局前向守卫（`int main(void){ int s = 1; return s; } int s = 3;`）。
test "issue337_local_shadow_fwd_global_allowed" {
  let loc = @source.SourceLoc::new(1, 30)
  let s_decl = {
    ..gdecl(
      @ast.Type::int(),
      "s",
      Some(@ast.Expr::Literal(3, loc, @ast.Type::int())),
    ),
    loc: @source.SourceLoc::new(2, 1),
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(
    with_main(
      gprog([s_decl]),
      @ast.Stmt::Block(
        [
          @ast.Stmt::VarDecl(
            @ast.Type::int(),
            "s",
            Some(@ast.Expr::Literal(1, loc, @ast.Type::int())),
            [],
            false,
            false,
            loc,
          ),
          @ast.Stmt::Return(
            Some(@ast.Expr::Identifier("s", loc, @ast.Type::int())),
            loc,
          ),
        ],
        loc,
      ),
    ),
  )
  assert_false(
    errs.exists(e => e.code == 3023),
    msg="局部遮蔽后文全局是合法形态，不得误报",
  )
}

///|
/// #337 负锚：后文函数**调用**面不升级 error——`int main(void){ return
/// f(); } int f(void){...}` 调用走 check_user_func 的 W3085 warning
///（#214 教学口径拍板），作值守卫不得渗入调用面（callee 不走
/// resolve_identifier 的 funcs 臂）。
test "issue337_call_face_not_escalated" {
  let loc = @source.SourceLoc::new(1, 27)
  let f_def : @ast.FuncDecl = {
    ..Default::default(),
    loc: @source.SourceLoc::new(2, 1),
    return_type: @ast.Type::int(),
    name: "f",
    params: [],
    body: Some(
      @ast.Stmt::Return(Some(@ast.Expr::Literal(0, loc, @ast.Type::int())), loc),
    ),
    source_file: "t.c",
  }
  let tc = TypeChecker::new()
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc: @source.SourceLoc::new(1, 1),
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(
      @ast.Stmt::Return(
        Some(@ast.Expr::Call("f", [], loc, @ast.Type::int())),
        loc,
      ),
    ),
    source_file: "t.c",
  }
  let (_, errs, _, _) = tc.check({ ..gprog([]), funcs: [main, f_def], })
  assert_false(
    errs.exists(e => e.code == 3023),
    msg="调用面前向引用维持 W3085 warning，不得升级 E3023 error",
  )
}

// ============================================================================
// #343（2026-10-28）：文件作用域 tentative 定义共存——C11 §6.9.2。
// J9：本批先证红后修（issue343_tentative_* 三锚修复前全红，负例四锚
// 防误放：双实定义/类型不一致/局部域仍拒）。
// ============================================================================

///|
/// #343 主体：tentative 定义 + 后文实定义——`int tent; int tent = 7;`
/// 合法共存（clang 零诊断）；Vitro 修复前 declare_var 落 E3001 兜底臂
///（同名语义四层无 tentative 分支）。
test "issue343_tentative_then_def_allowed" {
  let loc = @source.SourceLoc::new(3, 27)
  let t_tent = {
    ..gdecl(@ast.Type::int(), "tent", None),
    loc: @source.SourceLoc::new(1, 1),
  }
  let t_def = {
    ..gdecl(
      @ast.Type::int(),
      "tent",
      Some(@ast.Expr::Literal(7, loc, @ast.Type::int())),
    ),
    loc: @source.SourceLoc::new(2, 1),
  }
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc: @source.SourceLoc::new(3, 1),
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(
      @ast.Stmt::Return(
        Some(@ast.Expr::Identifier("tent", loc, @ast.Type::int())),
        loc,
      ),
    ),
    source_file: "t.c",
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check({ ..gprog([t_tent, t_def]), funcs: [main], })
  assert_false(
    errs.exists(e => e.code == 3001),
    msg="tentative 定义 + 后文实定义是合法共存形态（C11 6.9.2），不得报 E3001",
  )
}

///|
/// #343：双 tentative——`int a; int a;` 合法（两个均为 tentative 定义，
/// 零初始化语义不变）。
test "issue343_double_tentative_allowed" {
  let a1 = {
    ..gdecl(@ast.Type::int(), "a", None),
    loc: @source.SourceLoc::new(1, 1),
  }
  let a2 = {
    ..gdecl(@ast.Type::int(), "a", None),
    loc: @source.SourceLoc::new(2, 1),
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(gprog([a1, a2]))
  assert_false(
    errs.exists(e => e.code == 3001),
    msg="双 tentative 定义是合法形态，不得报 E3001",
  )
}

///|
/// #343：实定义先行 + 后随 tentative——`int t = 7; int t;` 合法
///（C11 §6.9.2p2 例 2 同款；后随 tentative 声明不构成重定义）。
test "issue343_def_then_tentative_allowed" {
  let loc = @source.SourceLoc::new(3, 27)
  let t_def = {
    ..gdecl(
      @ast.Type::int(),
      "t",
      Some(@ast.Expr::Literal(7, loc, @ast.Type::int())),
    ),
    loc: @source.SourceLoc::new(1, 1),
  }
  let t_tent = {
    ..gdecl(@ast.Type::int(), "t", None),
    loc: @source.SourceLoc::new(2, 1),
  }
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc: @source.SourceLoc::new(3, 1),
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(
      @ast.Stmt::Return(
        Some(@ast.Expr::Identifier("t", loc, @ast.Type::int())),
        loc,
      ),
    ),
    source_file: "t.c",
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check({ ..gprog([t_def, t_tent]), funcs: [main], })
  assert_false(
    errs.exists(e => e.code == 3001),
    msg="实定义 + 后随 tentative 声明是合法形态（C11 6.9.2p2），不得报 E3001",
  )
}

///|
/// #343 负锚：双实定义仍拒——`int a = 1; int a = 2;` 是真重定义
///（两声明均带初始化器，clang redefinition error），守卫不得误放。
test "issue343_double_def_still_rejected" {
  let loc = @source.SourceLoc::new(2, 10)
  let a1 = {
    ..gdecl(
      @ast.Type::int(),
      "a",
      Some(@ast.Expr::Literal(1, loc, @ast.Type::int())),
    ),
    loc: @source.SourceLoc::new(1, 1),
  }
  let a2 = {
    ..gdecl(
      @ast.Type::int(),
      "a",
      Some(@ast.Expr::Literal(2, loc, @ast.Type::int())),
    ),
    loc: @source.SourceLoc::new(2, 1),
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(gprog([a1, a2]))
  assert_true(
    errs.exists(e => e.code == 3001),
    msg="双实定义（均带初始化器）必须仍报 E3001",
  )
}

///|
/// #343 负锚：tentative 与实定义类型不一致仍拒——`int t; long long t = 7;`
/// clang 报 redeclaration with a different type。
test "issue343_tentative_type_mismatch_rejected" {
  let loc = @source.SourceLoc::new(2, 11)
  let t_tent = {
    ..gdecl(@ast.Type::int(), "t", None),
    loc: @source.SourceLoc::new(1, 1),
  }
  let t_def = {
    ..gdecl(
      @ast.Type::long_long(),
      "t",
      Some(@ast.Expr::Literal(7, loc, @ast.Type::long_long())),
    ),
    loc: @source.SourceLoc::new(2, 1),
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(gprog([t_tent, t_def]))
  assert_true(
    errs.exists(e => e.code == 3001),
    msg="tentative 与实定义类型不一致必须仍报 E3001",
  )
}

///|
/// #343 负锚：局部域无 tentative 概念——函数体内 `int t; int t;` 仍是
/// 重复声明（C11 §6.2.2 无链接对象同域重声明非法，clang redefinition；
/// tentative 仅文件作用域语义）。
test "issue343_local_no_tentative" {
  let loc = @source.SourceLoc::new(2, 5)
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(
    with_main(
      gprog([]),
      @ast.Stmt::Block(
        [
          @ast.Stmt::VarDecl(@ast.Type::int(), "t", None, [], false, false, loc),
          @ast.Stmt::VarDecl(@ast.Type::int(), "t", None, [], false, false, loc),
        ],
        loc,
      ),
    ),
  )
  assert_true(
    errs.exists(e => e.code == 3001),
    msg="函数体内同名双声明（无 tentative 语义）必须仍报 E3001",
  )
}

///|
/// #343 负锚（现状面防回归）：static tentative——`static int t; static
/// int t = 7;` 双 static 全局分支本就放行（内部链接保留最新）。
test "issue343_static_tentative_allowed" {
  let s1 = {
    ..{ ..gdecl(@ast.Type::int(), "st", None), is_static: true, },
    loc: @source.SourceLoc::new(1, 1),
  }
  let s2 = {
    ..{ ..gdecl(@ast.Type::int(), "st", None), is_static: true, },
    loc: @source.SourceLoc::new(2, 1),
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(gprog([s1, s2]))
  assert_false(
    errs.exists(e => e.code == 3001),
    msg="static tentative 共存维持既有放行行为",
  )
}

// ============================================================================
// PR #344 审阅处置批（2026-10-28）：P1 linkage 守卫 + P2-2 E3059 首值让位
// + P2-1 同行列级判据。J9：五锚修复前全红，三负例防误伤。
// ============================================================================

///|
/// 审阅处置批辅助：带自定义 loc 的 main 包装（with_main 的 loc 写死
/// (1,1)——同行列级判据锚需要非 (1,1) 起点）。
fn with_main_at(
  prog : @ast.ProgramNode,
  body : @ast.Stmt,
  loc : @source.SourceLoc,
) -> @ast.ProgramNode {
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
/// 审阅 P1：static 先行 + 非 static 后随（tentative 形态）——clang
/// "non-static declaration of 't' follows static declaration"（C11
/// 6.2.2p7 linkage 冲突）；#343 共存分支只看 tentative 不看 linkage，
/// 整族静默放行（s1/s1b/s1c 探针 rc=0 实锤）。
test "review344_static_then_nonstatic_rejected" {
  let st = {
    ..{ ..gdecl(@ast.Type::int(), "t", None), is_static: true, },
    loc: @source.SourceLoc::new(1, 1),
  }
  let nt = {
    ..gdecl(@ast.Type::int(), "t", None),
    loc: @source.SourceLoc::new(2, 1),
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(gprog([st, nt]))
  assert_true(
    errs.exists(e => e.code == 3001),
    msg="static 先行 + 非 static 后随必须报 E3001（linkage 冲突）",
  )
}

///|
/// 审阅 P1：static 定义先行 + 非 static tentative 后随——同族（s1c）。
test "review344_static_def_then_nonstatic_rejected" {
  let loc = @source.SourceLoc::new(1, 16)
  let st = {
    ..{
      ..gdecl(
        @ast.Type::int(),
        "t",
        Some(@ast.Expr::Literal(1, loc, @ast.Type::int())),
      ),
      is_static: true,
    },
    loc: @source.SourceLoc::new(1, 1),
  }
  let nt = {
    ..gdecl(@ast.Type::int(), "t", None),
    loc: @source.SourceLoc::new(2, 1),
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(gprog([st, nt]))
  assert_true(
    errs.exists(e => e.code == 3001),
    msg="static 定义先行 + 非 static 后随必须报 E3001",
  )
}

///|
/// 审阅 P2-2：**反向**（非 static tentative 先 + static 定义后随）clang
/// 零诊断放行（C11 6.2.2p5 后随 static 给 internal linkage——s8 探针
/// 实测；s9 同向零诊断）；旧 Vitro 报 E3059「static 全局在声明之前被
/// 使用」歪码（static_global_decl_lines 首值锚在后随条目）。
test "review344_nonstatic_then_static_allowed" {
  let loc = @source.SourceLoc::new(2, 27)
  let nt = {
    ..gdecl(@ast.Type::int(), "t", None),
    loc: @source.SourceLoc::new(1, 1),
  }
  let st = {
    ..{
      ..gdecl(
        @ast.Type::int(),
        "t",
        Some(@ast.Expr::Literal(5, loc, @ast.Type::int())),
      ),
      is_static: true,
    },
    loc: @source.SourceLoc::new(3, 1),
  }
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc: @source.SourceLoc::new(2, 1),
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(
      @ast.Stmt::Return(
        Some(@ast.Expr::Identifier("t", loc, @ast.Type::int())),
        loc,
      ),
    ),
    source_file: "t.c",
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check({ ..gprog([nt, st]), funcs: [main], })
  assert_false(
    errs.exists(e => e.code == 3059 || e.code == 3001),
    msg="非 static 先行 + static 后随是 clang 零诊断形态，不得报 E3059/E3001",
  )
}

///|
/// 审阅 P2-1：同行前向引用后文全局——`int main(void){ return s; }
/// int s = 3;` 单行形态，行号判据（严格小于）失效；列级判据（引用
/// col < 声明 col）收口（y1 探针 clang 报 undeclared、Vitro 静默 EXIT 3）。
test "review344_sameline_fwd_global_rejected" {
  // 单行：main 声明 col 1；return s 的 s 在 col 21；int s = 3 声明 col 34
  let use_loc = @source.SourceLoc::new(1, 21)
  let s_decl = {
    ..gdecl(
      @ast.Type::int(),
      "s",
      Some(@ast.Expr::Literal(3, use_loc, @ast.Type::int())),
    ),
    loc: @source.SourceLoc::new(1, 34),
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(
    with_main_at(
      gprog([s_decl]),
      @ast.Stmt::Return(
        Some(@ast.Expr::Identifier("s", use_loc, @ast.Type::int())),
        use_loc,
      ),
      @source.SourceLoc::new(1, 1),
    ),
  )
  assert_true(
    errs.exists(e => e.code == 3023),
    msg="同行前向引用后文全局应报 E3023（列级判据）",
  )
}

///|
/// 审阅 P2-1 负例：同行**声明先行**——`int s = 3; int main(void){ return
/// s; }`（声明 col 1 < 引用 col）零误报。
test "review344_sameline_decl_first_allowed" {
  let use_loc = @source.SourceLoc::new(1, 30)
  let s_decl = {
    ..gdecl(
      @ast.Type::int(),
      "s",
      Some(@ast.Expr::Literal(3, use_loc, @ast.Type::int())),
    ),
    loc: @source.SourceLoc::new(1, 1),
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(
    with_main_at(
      gprog([s_decl]),
      @ast.Stmt::Return(
        Some(@ast.Expr::Identifier("s", use_loc, @ast.Type::int())),
        use_loc,
      ),
      use_loc,
    ),
  )
  assert_false(
    errs.exists(e => e.code == 3023),
    msg="同行声明先行是合法形态，不得误报",
  )
}

///|
/// 审阅 P2-1：同行函数名作值前向——`int (*fp)(void) = f; int f(void)
/// {...}` 单行（y5 探针 clang 报 undeclared、Vitro 静默）。
test "review344_sameline_fwd_func_addr_rejected" {
  let use_loc = @source.SourceLoc::new(1, 22)
  let fp_decl = {
    ..gdecl(
      @ast.Type::function_pointer(@ast.Type::int(), []),
      "fp",
      Some(@ast.Expr::Identifier("f", use_loc, @ast.Type::int())),
    ),
    loc: @source.SourceLoc::new(1, 1),
  }
  let f_def : @ast.FuncDecl = {
    ..Default::default(),
    loc: @source.SourceLoc::new(1, 28),
    return_type: @ast.Type::int(),
    name: "f",
    params: [],
    body: Some(
      @ast.Stmt::Return(
        Some(@ast.Expr::Literal(1, use_loc, @ast.Type::int())),
        use_loc,
      ),
    ),
    source_file: "t.c",
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check({ ..gprog([fp_decl]), funcs: [f_def], })
  assert_true(
    errs.exists(e => e.code == 3023),
    msg="同行函数名作值前向引用应报 E3023（列级判据）",
  )
}

///|
/// 审阅 P2-1：同行调用前向——`int main(void){ return f(); } int f(void)
/// {...}` 单行（y6 探针 clang 报 error、Vitro 连 W3085 都不给——
/// first_decl_line 严格小于同行失效）。
test "review344_sameline_call_warns" {
  let use_loc = @source.SourceLoc::new(1, 27)
  let f_def : @ast.FuncDecl = {
    ..Default::default(),
    loc: @source.SourceLoc::new(1, 33),
    return_type: @ast.Type::int(),
    name: "f",
    params: [],
    body: Some(
      @ast.Stmt::Return(
        Some(@ast.Expr::Literal(1, use_loc, @ast.Type::int())),
        use_loc,
      ),
    ),
    source_file: "t.c",
  }
  let tc = TypeChecker::new()
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc: @source.SourceLoc::new(1, 1),
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(
      @ast.Stmt::Return(
        Some(@ast.Expr::Call("f", [], use_loc, @ast.Type::int())),
        use_loc,
      ),
    ),
    source_file: "t.c",
  }
  let (_, errs, warns, _) = tc.check({ ..gprog([]), funcs: [main, f_def], })
  assert_false(
    errs.exists(e => e.code == 3023),
    msg="调用面维持 error 零",
  )
  assert_true(
    warns.exists(w => w.code == 3085),
    msg="同行调用前向必须给 W3085（列级判据）",
  )
}

///|
/// 审阅 P1 负例：extern 跟随 static——`static int t; extern int t;`
///（C11 6.2.2p4 extern 跟随 static 保持 internal linkage）clang 零
/// 诊断，走既有 extern 共存分支不受 linkage 守卫波及（s10 探针）。
test "review344_extern_follows_static_allowed" {
  let st = {
    ..{ ..gdecl(@ast.Type::int(), "t", None), is_static: true, },
    loc: @source.SourceLoc::new(1, 1),
  }
  let et = {
    ..gdecl(@ast.Type::int(), "t", None, is_extern=true),
    loc: @source.SourceLoc::new(2, 1),
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(gprog([st, et]))
  assert_false(
    errs.exists(e => e.code == 3001),
    msg="extern 跟随 static 是合法形态（6.2.2p4），不得报 E3001",
  )
}

///|
/// #369（2026-10-29，#368 突变抽查）：tentative「AND 定稿」三声明形态——
/// `int x = 5; int x; int x = 6;`（前实 → tent → 实）第三笔实定义必须落
/// E3001 兜底（双实定义仍拒）。AND→OR 突变（后随 tentative 把已定稿符号
/// 降级回 tentative）下本锚红——此前 wbtest+digest 双绿放过的零锚面。
test "issue369_real_tent_real_rejected" {
  let loc1 = @source.SourceLoc::new(1, 1)
  let loc2 = @source.SourceLoc::new(2, 1)
  let loc3 = @source.SourceLoc::new(3, 1)
  let real1 : @ast.GlobalDecl = {
    ..gdecl(
      @ast.Type::int(),
      "x",
      Some(@ast.Expr::Literal(5, loc1, @ast.Type::int())),
    ),
    loc: loc1,
  }
  let tent : @ast.GlobalDecl = {
    ..gdecl(@ast.Type::int(), "x", None),
    loc: loc2,
  }
  let real2 : @ast.GlobalDecl = {
    ..gdecl(
      @ast.Type::int(),
      "x",
      Some(@ast.Expr::Literal(6, loc3, @ast.Type::int())),
    ),
    loc: loc3,
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(gprog([real1, tent, real2]))
  assert_true(
    errs.exists(e => e.code == 3001),
    msg="前实→tentative→实（第三笔实定义）必须报 E3001（双实定义仍拒，AND 定稿语义）",
  )
}

///|
/// #370（2026-10-29，#368 突变抽查）：列级判据同族两处的 E3058 侧——
/// `int main(void){ return f(); } static int f(void){...}` 同行、用点列
/// 先于声明列，必须报 E3058（W3085 侧已有 review344_sameline_call_warns
/// 锚；本侧列级判据删除后静默漏报，wbtest+digest 双绿放过的零锚面）。
test "issue370_sameline_static_call_e3058" {
  let use_loc = @source.SourceLoc::new(1, 27)
  let f_def : @ast.FuncDecl = {
    ..Default::default(),
    loc: @source.SourceLoc::new(1, 33),
    return_type: @ast.Type::int(),
    name: "f",
    params: [],
    body: Some(
      @ast.Stmt::Return(
        Some(@ast.Expr::Literal(7, use_loc, @ast.Type::int())),
        use_loc,
      ),
    ),
    source_file: "t.c",
    is_static: true,
  }
  let tc = TypeChecker::new()
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc: @source.SourceLoc::new(1, 1),
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(
      @ast.Stmt::Return(
        Some(@ast.Expr::Call("f", [], use_loc, @ast.Type::int())),
        use_loc,
      ),
    ),
    source_file: "t.c",
  }
  let (_, errs, _, _) = tc.check({ ..gprog([]), funcs: [main, f_def], })
  assert_true(
    errs.exists(e => e.code == 3058),
    msg="同行 static 函数先用后声明必须报 E3058（列级判据 E3058 侧）",
  )
}

///|
/// PR #375 审阅 P1-2（2026-10-30）：单行「先定义后调用」合法形态——
/// `static int f(void){ return 7; } int main(void){ return f(); }`
/// （clang 零诊断）。E3058 同行列级判据的 &&→|| 突变会让
/// `loc.line == first_decl_line` 单条件成立 ⇒ 对**一切同行使用**（含合法的
/// 定义后调用）误报 E3058——此前该突变双杀阵全绿（引擎闸 P1-1 缺陷期假绿）
/// 且被误登记为「实践等价」豁免；本锚落地后该豁免条目已删。
test "review375_sameline_define_then_use_legal" {
  let def_loc = @source.SourceLoc::new(1, 1)
  let use_loc = @source.SourceLoc::new(1, 46)
  let f_def : @ast.FuncDecl = {
    ..Default::default(),
    loc: def_loc,
    return_type: @ast.Type::int(),
    name: "f",
    params: [],
    body: Some(
      @ast.Stmt::Return(
        Some(@ast.Expr::Literal(7, def_loc, @ast.Type::int())),
        def_loc,
      ),
    ),
    source_file: "t.c",
    is_static: true,
  }
  let tc = TypeChecker::new()
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc: @source.SourceLoc::new(1, 28),
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(
      @ast.Stmt::Return(
        Some(@ast.Expr::Call("f", [], use_loc, @ast.Type::int())),
        use_loc,
      ),
    ),
    source_file: "t.c",
  }
  let (_, errs, _, _) = tc.check({ ..gprog([]), funcs: [f_def, main], })
  assert_false(
    errs.exists(e => e.code == 3058),
    msg="单行先定义后调用（合法）不得报 E3058——列级判据 &&→|| 突变的杀伤锚",
  )
  assert_false(
    errs.exists(e => e.code == 3023),
    msg="单行先定义后调用（合法）不得报 E3023",
  )
}
