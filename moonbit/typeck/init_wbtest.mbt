///|
/// T5-d init 面白盒锚：数组尺寸推断（一维/字符串字面量两轨）/ 超量
/// E3005 / E3008 / struct 初始化（位置 + designated + 嵌套）/ 多维
/// 扁平标量填充。

///|
/// 全局数组 `int a[] = {1,2,3}`：dims[0] 与 array_size 推断为 3；超量
/// 元素报 E3005（推断后按 3 判）。
test "init_array_size_inference" {
  let loc = @source.SourceLoc::new(1, 1)
  fn elem(v : Int, loc : @source.SourceLoc) -> @ast.InitElement {
    { designators: [], value: @ast.Expr::Literal(v, loc, @ast.Type::int()), }
  }
  let g : @ast.GlobalDecl = {
    loc,
    ty: @ast.Type::Array(@ast.Type::int(), -1, [-1], false, false, []),
    name: "a",
    init: Some(
      @ast.Expr::InitList(
        [elem(1, loc), elem(2, loc), elem(3, loc)],
        loc,
        @ast.Type::void_type(),
      ),
    ),
    is_static: false,
    is_extern: false,
    source_file: "t.c",
  }
  let prog : @ast.ProgramNode = {
    structs: [],
    unions: [],
    globals: [g],
    funcs: [],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
  let tc = TypeChecker::new()
  let (typed, errs, _, _) = tc.check(prog)
  assert_eq(errs.length(), 0)
  match typed.globals[0].ty {
    @ast.Type::Array(_, size, dims, _, _, _) => {
      assert_eq(dims[0], 3)
      assert_eq(size, 3)
    }
    _ => fail("应推断为数组")
  }
  // 超量：int b[2] = {1,2,3} → E3005
  let g2 : @ast.GlobalDecl = {
    loc,
    ty: @ast.Type::array_of(@ast.Type::int(), [2]),
    name: "b",
    init: Some(
      @ast.Expr::InitList(
        [elem(1, loc), elem(2, loc), elem(3, loc)],
        loc,
        @ast.Type::void_type(),
      ),
    ),
    is_static: false,
    is_extern: false,
    source_file: "t.c",
  }
  let prog2 : @ast.ProgramNode = { ..prog, globals: [g2], }
  let tc2 = TypeChecker::new()
  let (_, errs2, _, _) = tc2.check(prog2)
  assert_eq(errs2.length(), 1)
  assert_true(errs2[0].code == 3005)
}

///|
/// 字符串字面量轨：`char s[] = "ab"` → array_size=3（dims 不回写——
/// Rust 同形）；`char t[2] = "ab"` → E3008 超长。
test "init_string_literal_track" {
  let loc = @source.SourceLoc::new(1, 1)
  let s : @ast.GlobalDecl = {
    loc,
    ty: @ast.Type::Array(@ast.Type::char(), -1, [-1], false, false, []),
    name: "s",
    init: Some(@ast.Expr::StringLiteral("ab", loc, @ast.Type::void_type())),
    is_static: false,
    is_extern: false,
    source_file: "t.c",
  }
  let prog : @ast.ProgramNode = {
    structs: [],
    unions: [],
    globals: [s],
    funcs: [],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
  let tc = TypeChecker::new()
  let (typed, errs, _, _) = tc.check(prog)
  assert_eq(errs.length(), 0)
  match typed.globals[0].ty {
    @ast.Type::Array(_, size, dims, _, _, _) => {
      assert_eq(size, 3) // 2 字节 + NUL
      assert_eq(dims[0], -1) // dims 不回写（Rust 现状照搬）
    }
    _ => fail("char 数组")
  }
  let t : @ast.GlobalDecl = {
    loc,
    ty: @ast.Type::array_of(@ast.Type::char(), [2]),
    name: "t",
    init: Some(@ast.Expr::StringLiteral("ab", loc, @ast.Type::void_type())),
    is_static: false,
    is_extern: false,
    source_file: "t.c",
  }
  let prog2 : @ast.ProgramNode = { ..prog, globals: [t], }
  let tc2 = TypeChecker::new()
  let (_, errs2, _, _) = tc2.check(prog2)
  assert_eq(errs2.length(), 1)
  assert_true(errs2[0].code == 3008)
}

///|
/// struct 初始化三面：位置初始化逐字段定型 / designated 未知字段 E3042 /
/// 混合使用 E3005。
test "init_struct_tracks" {
  let loc = @source.SourceLoc::new(1, 1)
  let pt : @ast.StructDecl = {
    loc,
    name: "P",
    fields: [
      { ty: @ast.Type::int(), name: "x", },
      { ty: @ast.Type::int(), name: "y", },
    ],
  }
  fn init_list(
    elems : Array[@ast.InitElement],
    loc : @source.SourceLoc,
  ) -> @ast.Expr {
    @ast.Expr::InitList(elems, loc, @ast.Type::void_type())
  }
  fn lit(v : Int, loc : @source.SourceLoc) -> @ast.Expr {
    @ast.Expr::Literal(v, loc, @ast.Type::int())
  }
  // 合法定位初始化
  let ok_g : @ast.GlobalDecl = {
    loc,
    ty: @ast.Type::struct_type("P"),
    name: "p",
    init: Some(
      init_list(
        [
          { designators: [], value: lit(1, loc), },
          { designators: [], value: lit(2, loc), },
        ],
        loc,
      ),
    ),
    is_static: false,
    is_extern: false,
    source_file: "t.c",
  }
  // designated 未知字段 → E3042
  let bad_field_g : @ast.GlobalDecl = {
    loc,
    ty: @ast.Type::struct_type("P"),
    name: "q",
    init: Some(
      init_list(
        [{ designators: [@ast.Designator::Field("z")], value: lit(1, loc), }],
        loc,
      ),
    ),
    is_static: false,
    is_extern: false,
    source_file: "t.c",
  }
  // 混合 → E3005
  let mix_g : @ast.GlobalDecl = {
    loc,
    ty: @ast.Type::struct_type("P"),
    name: "r",
    init: Some(
      init_list(
        [
          { designators: [@ast.Designator::Field("x")], value: lit(1, loc), },
          { designators: [], value: lit(2, loc), },
        ],
        loc,
      ),
    ),
    is_static: false,
    is_extern: false,
    source_file: "t.c",
  }
  let prog : @ast.ProgramNode = {
    structs: [pt],
    unions: [],
    globals: [ok_g],
    funcs: [],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(prog)
  assert_eq(errs.length(), 0)
  let tc2 = TypeChecker::new()
  let (_, errs2, _, _) = tc2.check({ ..prog, globals: [bad_field_g], })
  assert_eq(errs2.length(), 1)
  assert_true(errs2[0].code == 3042)
  let tc3 = TypeChecker::new()
  let (_, errs3, _, _) = tc3.check({ ..prog, globals: [mix_g], })
  assert_eq(errs3.length(), 1)
  assert_true(errs3[0].code == 3005)
}

///|
/// 多维扁平标量填充：`int m[2][3] = {1,2,3,4,5,6}` 合法（行主序）；
/// 嵌套超维 E3005。
test "init_multidim_flat_scalar" {
  let loc = @source.SourceLoc::new(1, 1)
  fn lit(v : Int, loc : @source.SourceLoc) -> @ast.Expr {
    @ast.Expr::Literal(v, loc, @ast.Type::int())
  }
  fn flat(elems : Array[Int], loc : @source.SourceLoc) -> @ast.Expr {
    @ast.Expr::InitList(
      elems.map(v => { designators: [], value: lit(v, loc), }),
      loc,
      @ast.Type::void_type(),
    )
  }
  let m : @ast.GlobalDecl = {
    loc,
    ty: @ast.Type::array_of(@ast.Type::int(), [2, 3]),
    name: "m",
    init: Some(flat([1, 2, 3, 4, 5, 6], loc)),
    is_static: false,
    is_extern: false,
    source_file: "t.c",
  }
  let prog : @ast.ProgramNode = {
    structs: [],
    unions: [],
    globals: [m],
    funcs: [],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(prog)
  assert_eq(errs.length(), 0)
  // 7 元素超 2×3 → E3005
  let m2 : @ast.GlobalDecl = {
    ..m,
    init: Some(flat([1, 2, 3, 4, 5, 6, 7], loc)),
  }
  let tc2 = TypeChecker::new()
  let (_, errs2, _, _) = tc2.check({ ..prog, globals: [m2], })
  assert_eq(errs2.length(), 1)
  assert_true(errs2[0].code == 3005)
}
