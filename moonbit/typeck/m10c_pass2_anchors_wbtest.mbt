///|
/// M10c A-1/A-2/A-3 回归锚（审阅 v2 批 B9 第二批，2026-11-02，#433）。
/// 红形态证据 = 审阅现场 probes p1a/p1c/p3/p4/p5 CLI 跑红实录
///（p1a rv 12 vs clang 24；p1c 零诊断 vs clang error；p3/p4/p5 零诊断
/// vs 三方 error）。

///|
/// M10c A-3a：variadic 位入签名判等——`int f(int,...)` 与 `int f(int)`
/// 旧判等放行（conflicting types 漏报）。
test "m10c_params_eq_variadic_in_signature" {
  let int_ty = @ast.Type::int()
  assert_true(
    params_eq([int_ty], [int_ty], va=false, vb=false),
    msg="同宽同 variadic 判等",
  )
  assert_false(
    params_eq([int_ty], [int_ty], va=false, vb=true),
    msg="variadic 位不同 ⇒ 签名不等（M10c A-3a）",
  )
  assert_false(
    params_eq([int_ty], [int_ty], va=true, vb=false),
    msg="反向 variadic 位不同同判不等",
  )
  assert_true(
    params_eq([int_ty], [int_ty], va=true, vb=true),
    msg="双 variadic 判等",
  )
}

///|
/// M10c A-1：多维不完整数组升级——`extern int m[][3]; int m[2][3];`
/// 升级后 array_size 应为各维乘积 6（旧判据 es==-1 多维永不触发 +
/// 旧重建写首维 2；clang sizeof=24=6×4）。一维对照 `extern int a[];
/// int a[4];` 行为不变（16）。
test "m10c_incomplete_2d_upgrade_product_size" {
  let loc = @source.SourceLoc::new(1, 1)
  let int_ty = @ast.Type::int()
  let g1 : @ast.GlobalDecl = {
    loc,
    ty: @ast.Type::Array(int_ty, 3, [-1, 3], false, false, []),
    name: "m",
    init: None,
    is_static: false,
    is_extern: true,
    source_file: "t.c",
  }
  let g2 : @ast.GlobalDecl = {
    loc,
    ty: @ast.Type::Array(int_ty, 6, [2, 3], false, false, []),
    name: "m",
    init: None,
    is_static: false,
    is_extern: false,
    source_file: "t.c",
  }
  // sizeof(m) 端到端：升级成功 ⇒ m 完整 ⇒ A-2 查不触发零诊断；
  // 升级失败（判据或乘积重建任一回退）⇒ m 仍不完整 ⇒ E3076 红。
  let main_fn : @ast.FuncDecl = {
    ..Default::default(),
    loc,
    name: "main",
    return_type: @ast.Type::int(),
    params: [],
    body: Some(
      @ast.Stmt::Return(
        Some(
          @ast.Expr::Sizeof(
            None,
            Some(@ast.Expr::Identifier("m", loc, int_ty)),
            loc,
            @ast.Type::int(),
          ),
        ),
        loc,
      ),
    ),
    source_file: "t.c",
  }
  let prog : @ast.ProgramNode = {
    structs: [],
    unions: [],
    globals: [g1, g2],
    funcs: [main_fn],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(prog)
  assert_eq(
    errs.length(),
    0,
    msg="不完整→完整升级是合法 C（clang 接受 sizeof=24）；升级失败会经 A-2 不完整查报 E3076——实得 \{errs.length()} 条 error",
  )
}

///|
/// M10c A-3c + A-3a 端到端：原型→定义→第二定义漏检 + variadic 冲突。
/// （构造走 Pass2 直查面：FuncDecl 三声明同名。）
fn m10c_func(
  name : String,
  variadic : Bool,
  has_body : Bool,
  loc : @source.SourceLoc,
) -> @ast.FuncDecl {
  {
    ..Default::default(),
    loc,
    name,
    return_type: @ast.Type::int(),
    params: [{ ty: @ast.Type::int(), name: "x", loc, default: None, }],
    is_variadic: variadic,
    body: if has_body {
      Some(@ast.Stmt::Block([], loc))
    } else {
      None
    },
    source_file: "t.c",
  }
}

///|
test "m10c_proto_def_def_second_caught" {
  let loc = @source.SourceLoc::new(1, 1)
  let prog : @ast.ProgramNode = {
    structs: [],
    unions: [],
    globals: [],
    funcs: [
      m10c_func("f", false, false, loc),
      m10c_func("f", false, true, loc),
      m10c_func("f", false, true, loc),
    ],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(prog)
  assert_eq(
    errs.length(),
    1,
    msg="原型+定义+定义的第二个定义应报 E3003（旧 is_definition 恒 false 漏检；实得 \{errs.length()}）",
  )
}

///|
test "m10c_variadic_conflict_caught" {
  let loc = @source.SourceLoc::new(1, 1)
  let prog : @ast.ProgramNode = {
    structs: [],
    unions: [],
    globals: [],
    funcs: [m10c_func("g", true, false, loc), m10c_func("g", false, true, loc)],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(prog)
  assert_eq(
    errs.length(),
    1,
    msg="int f(int,...) 与 int f(int) 应判签名冲突（旧 variadic 不参与判等零诊断；实得 \{errs.length()}）",
  )
}

///|
test "m10c_static_nonsplit_cross_caught" {
  let loc = @source.SourceLoc::new(1, 1)
  let f_static : @ast.FuncDecl = {
    ..Default::default(),
    loc,
    name: "h",
    return_type: @ast.Type::int(),
    params: [{ ty: @ast.Type::int(), name: "x", loc, default: None, }],
    is_static: true,
    body: Some(@ast.Stmt::Block([], loc)),
    source_file: "t.c",
  }
  let f_plain : @ast.FuncDecl = {
    ..Default::default(),
    loc,
    name: "h",
    return_type: @ast.Type::int(),
    params: [{ ty: @ast.Type::int(), name: "x", loc, default: None, }],
    body: Some(@ast.Stmt::Block([], loc)),
    source_file: "t.c",
  }
  let prog : @ast.ProgramNode = {
    structs: [],
    unions: [],
    globals: [],
    funcs: [f_static, f_plain],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(prog)
  assert_eq(
    errs.length(),
    1,
    msg="static 与非 static 同名应报链接性冲突（旧双表分治零交叉；实得 \{errs.length()}）",
  )
}
