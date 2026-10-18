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
      @ast.Stmt::VarDecl(@ast.Type::struct_type("S"), "s", None, [], false, loc),
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
      @ast.Stmt::VarDecl(@ast.Type::struct_type("N"), "n", None, [], false, loc),
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
