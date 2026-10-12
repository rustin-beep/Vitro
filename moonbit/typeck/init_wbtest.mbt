///|
/// T5-d init 面白盒锚：数组尺寸推断（一维/字符串字面量两轨）/ 超量
/// W3005 / W3008（#50 批②降级，原 E3005/E3008）/ struct 初始化（位置 + designated + 嵌套）/ 多维
/// 扁平标量填充。

///|
/// 全局数组 `int a[] = {1,2,3}`：dims[0] 与 array_size 推断为 3；超量
/// 元素报 W3005（推断后按 3 判；#50 批②降级）。
test "init_array_size_inference" {
  let loc = @source.SourceLoc::new(1, 1)
  fn elem(v : Int, loc : @source.SourceLoc) -> @ast.InitElement {
    { designators: [], value: @ast.Expr::Literal(v, loc, @ast.Type::int()), }
  }
  let g : @ast.GlobalDecl = {
    ..Default::default(),
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
  // 超量：int b[2] = {1,2,3} → W3005（#50 批②降级）
  let g2 : @ast.GlobalDecl = {
    ..Default::default(),
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
    source_file: "t.c",
  }
  let prog2 : @ast.ProgramNode = { ..prog, globals: [g2], }
  let tc2 = TypeChecker::new()
  // #50 批②：E3005→W3005（Clang 默认 warning）——断言移 warnings 通道
  let (_, _, errs2, _) = tc2.check(prog2)
  assert_eq(errs2.length(), 1)
  assert_true(errs2[0].code == 3005)
}

///|
/// 字符串字面量轨：`char s[] = "ab"` → array_size=3（dims 不回写——
/// Rust 同形）；`char t[2] = "ab"` → E3008 超长。
test "init_string_literal_track" {
  let loc = @source.SourceLoc::new(1, 1)
  let s : @ast.GlobalDecl = {
    ..Default::default(),
    loc,
    ty: @ast.Type::Array(@ast.Type::char(), -1, [-1], false, false, []),
    name: "s",
    init: Some(@ast.Expr::StringLiteral("ab", loc, @ast.Type::void_type())),
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
    ..Default::default(),
    loc,
    ty: @ast.Type::array_of(@ast.Type::char(), [2]),
    name: "t",
    init: Some(@ast.Expr::StringLiteral("ab", loc, @ast.Type::void_type())),
    source_file: "t.c",
  }
  let prog2 : @ast.ProgramNode = { ..prog, globals: [t], }
  let tc2 = TypeChecker::new()
  // #50 批②：E3008→W3008——断言移 warnings 通道
  let (_, _, errs2, _) = tc2.check(prog2)
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
    ..Default::default(),
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
    source_file: "t.c",
  }
  // designated 未知字段 → E3042
  let bad_field_g : @ast.GlobalDecl = {
    ..Default::default(),
    loc,
    ty: @ast.Type::struct_type("P"),
    name: "q",
    init: Some(
      init_list(
        [{ designators: [@ast.Designator::Field("z")], value: lit(1, loc), }],
        loc,
      ),
    ),
    source_file: "t.c",
  }
  // 混合 → E3005
  let mix_g : @ast.GlobalDecl = {
    ..Default::default(),
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
  let (_, _, errs3, _) = tc3.check({ ..prog, globals: [mix_g], })
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
    ..Default::default(),
    loc,
    ty: @ast.Type::array_of(@ast.Type::int(), [2, 3]),
    name: "m",
    init: Some(flat([1, 2, 3, 4, 5, 6], loc)),
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
  let (_, _, errs2, _) = tc2.check({ ..prog, globals: [m2], })
  assert_eq(errs2.length(), 1)
  assert_true(errs2[0].code == 3005)
}

///|
/// #75 缺口 3 红锚（2026-10-12，C11 6.7.9p14）：char[] 成员的字符串字面量
/// 初始化合法——`struct S { char s[64]; } a = {"Hi"};`（顶层 char[] 同形
/// 能过、struct 成员被 E3006 误拒：check_field_value 落 else 兜底把
/// "Hi" 定型 char[3] 去比 char[64]）。
test "struct_char_array_member_string_init_issue75_g3" {
  let loc = @source.SourceLoc::new(3, 20)
  let tc = TypeChecker::new()
  tc.enter_scope()
  // char s[64] 字段 ← "Hi"
  let field_ty = @ast.Type::array_of(@ast.Type::char(), [64])
  let val = @ast.Expr::StringLiteral("Hi", loc, @ast.Type::void_type())
  ignore(tc.check_field_value(field_ty, "s", val, loc))
  assert_eq(
    tc.errors.length(),
    0,
    msg="char[] 成员收字符串字面量合法（E3006 假阳性）",
  )
  // 溢出仍警（W3008 面）：char s[2] ← "Hi"（3 字节超 2）
  let tc2 = TypeChecker::new()
  tc2.enter_scope()
  let small_ty = @ast.Type::array_of(@ast.Type::char(), [2])
  ignore(tc2.check_field_value(small_ty, "s", val, loc))
  assert_eq(tc2.errors.length(), 0, msg="超长不升 error")
  assert_eq(tc2.warnings.length(), 1, msg="超长维持 W3008")
  // 非 char 数组成员收字符串仍拒（int s[4] ← "Hi"）
  let tc3 = TypeChecker::new()
  tc3.enter_scope()
  let int_arr = @ast.Type::array_of(@ast.Type::int(), [4])
  ignore(tc3.check_field_value(int_arr, "s", val, loc))
  assert_eq(tc3.errors.length(), 1, msg="非 char 数组收字符串维持拒")
}
