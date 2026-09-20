///|
/// B6 资产照搬：`implicit_cast_target` 十例判据（Rust lib.rs:622-712
/// 内联单测同断言——转换表逐臂锚；改一臂此锚红）。
test "implicit_cast_target_b6_table" {
  let int = @ast.Type::int()
  let double = @ast.Type::double()
  let float = @ast.Type::float()
  let char_ = @ast.Type::char()
  let long_long = @ast.Type::long_long()
  let p = @ast.Type::pointer_to(int)
  assert_true(implicit_cast_target(int, double) is Some(Double(_)))
  assert_true(implicit_cast_target(double, int) is Some(Int(_, _)))
  assert_true(implicit_cast_target(float, int) is Some(Int(_, _)))
  assert_true(implicit_cast_target(int, float) is Some(Float(_)))
  assert_true(implicit_cast_target(char_, long_long) is Some(LongLong(_, _)))
  assert_true(implicit_cast_target(long_long, char_) is Some(Char(_, _)))
  // 指针不参与隐式标量转换
  assert_true(implicit_cast_target(p, int) is None)
  assert_true(implicit_cast_target(int, p) is None)
  // 引用类型不参与（前置排除）
  let r = @ast.Type::Reference(int, false)
  assert_true(implicit_cast_target(r, double) is None)
  assert_true(implicit_cast_target(double, r) is None)
}

///|
/// insert_implicit_cast 两形态（B6 后两例）：
/// int 字面量 → Cast{Double}；float 字面量 → int 时 Cast{Int}（非 double
/// 目标不走 FloatLiteral 重定型特例）；FloatLiteral→double 特例只重定型。
test "insert_implicit_cast_shapes" {
  let loc = @source.SourceLoc::new(1, 1)
  let lit : @ast.Expr = @ast.Expr::Literal(42, loc, @ast.Type::int())
  match insert_implicit_cast(lit, @ast.Type::double()) {
    Cast(_, target_type, _, _) => assert_true(target_type is Double(_))
    _ => fail("int 字面量→double 应包 Cast")
  }
  let flit : @ast.Expr = @ast.Expr::FloatLiteral(2.5, loc, @ast.Type::float())
  match insert_implicit_cast(flit, @ast.Type::int()) {
    Cast(_, target_type, _, _) => assert_true(target_type is Int(_, _))
    _ => fail("float 字面量→int 应包 Cast")
  }
  let flit2 : @ast.Expr = @ast.Expr::FloatLiteral(2.5, loc, @ast.Type::float())
  match insert_implicit_cast(flit2, @ast.Type::double()) {
    FloatLiteral(_, _, ty) => assert_true(ty is Double(_))
    _ => fail("float 字面量→double 应重定型不插 Cast")
  }
}

///|
/// Pass 1 白盒锚：T-P0-8 值成员环检测（E3072——学生漏 `*` 的经典防线；
/// 含指针豁免）。
test "pass1_struct_cycle" {
  let loc = @source.SourceLoc::new(1, 1)
  // 环：struct Node { struct Node next; }
  let node : @ast.StructDecl = {
    name: "Node",
    fields: [{ ty: @ast.Type::struct_type("Node"), name: "next", }],
    loc,
  }
  let prog : @ast.ProgramNode = {
    structs: [node],
    unions: [],
    funcs: [],
    globals: [],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(prog)
  assert_eq(errs.length(), 1)
  assert_true(errs[0].code == 3072)
  // 指针成员不构成环
  let node_ptr : @ast.StructDecl = {
    name: "Node2",
    fields: [
      {
        ty: @ast.Type::pointer_to(@ast.Type::struct_type("Node2")),
        name: "next",
      },
    ],
    loc,
  }
  let prog2 : @ast.ProgramNode = {
    structs: [node_ptr],
    unions: [],
    funcs: [],
    globals: [],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
  let tc2 = TypeChecker::new()
  let (_, errs2, _, _) = tc2.check(prog2)
  assert_eq(errs2.length(), 0)
}

///|
/// 环检测取符号表首版而非当前声明（Rust lib.rs:139-141 遍历 sym.fields
/// ——审阅 F1 实锤分叉的红锚；双向对抗：次版自环不得多报、首版自环
/// 不得漏报）。
test "pass1_cycle_uses_symbol_table_not_decl" {
  let loc = @source.SourceLoc::new(1, 1)
  fn decl(name : String, self_ref : Bool) -> @ast.StructDecl {
    {
      name,
      fields: [
        {
          ty: if self_ref {
            @ast.Type::struct_type(name)
          } else {
            @ast.Type::int()
          },
          name: "f",
        },
      ],
      loc,
    }
  }
  // 对抗 1：首版无环 + 次版自环（重复定义）——只报 E3002，
  // 不得多报假 E3072（次版 fields 不参与环检测）
  let prog : @ast.ProgramNode = {
    structs: [decl("N", false), decl("N", true)],
    unions: [],
    funcs: [],
    globals: [],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(prog)
  assert_eq(errs.length(), 1)
  assert_true(errs[0].code == 3002)
  // 对抗 2：首版自环 + 次版无环（重复定义）——三条：每个声明各跑一次
  // 环检测（fields 均取符号表首版=自环版）→ 2×E3072 + 1×E3002
  //（双侧实测逐位同：Rust lib.rs:139-141 同语义；本期望初版写 2 条
  // 系脑测错误，实跑纠正——实测大于脑测）
  let prog2 : @ast.ProgramNode = {
    structs: [decl("N", true), decl("N", false)],
    unions: [],
    funcs: [],
    globals: [],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
  let tc2 = TypeChecker::new()
  let (_, errs2, _, _) = tc2.check(prog2)
  assert_eq(errs2.length(), 3)
  // 顺序：注册循环先完（E3002），环检测循环后跑（2×E3072）
  assert_true(errs2[0].code == 3002)
  assert_true(errs2[1].code == 3072)
  assert_true(errs2[2].code == 3072)
  // union 同款：首版无环 + 次版自环——只报 E3002
  let prog3 : @ast.ProgramNode = {
    structs: [],
    unions: [decl("U", false), decl("U", true)],
    funcs: [],
    globals: [],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
  let tc3 = TypeChecker::new()
  let (_, errs3, _, _) = tc3.check(prog3)
  assert_eq(errs3.length(), 1)
  assert_true(errs3[0].code == 3002)
}

///|
/// U1#12 三形状锚（check_array_dims_legality：负尺寸 / -1 无初始化器 /
/// 显式零——修复前零诊断静默接受）+ 豁免面（VLA / 有初始化器）。
test "array_dims_legality_u1_12" {
  let loc = @source.SourceLoc::new(1, 1)
  fn dims_of(first : Int) -> @ast.Type {
    @ast.Type::array_of(@ast.Type::int(), [first])
  }
  // 负尺寸
  let tc = TypeChecker::new()
  tc.check_array_dims_legality(dims_of(-5), false, loc)
  assert_eq(tc.errors.length(), 1)
  assert_true(tc.errors[0].code == 2002)
  // -1 无初始化器
  let tc2 = TypeChecker::new()
  tc2.check_array_dims_legality(dims_of(-1), false, loc)
  assert_eq(tc2.errors.length(), 1)
  // -1 有初始化器（推断路径，合法）
  let tc3 = TypeChecker::new()
  tc3.check_array_dims_legality(dims_of(-1), true, loc)
  assert_eq(tc3.errors.length(), 0)
  // 显式零
  let tc4 = TypeChecker::new()
  tc4.check_array_dims_legality(dims_of(0), true, loc)
  assert_eq(tc4.errors.length(), 1)
  // VLA 豁免
  let tc5 = TypeChecker::new()
  match dims_of(0) {
    Array(elem, size, dims, is_const, _, _) =>
      tc5.check_array_dims_legality(
        @ast.Type::Array(elem, size, dims, is_const, true, []),
        true,
        loc,
      )
    _ => fail("array 形态")
  }
  assert_eq(tc5.errors.length(), 0)
}

///|
/// declare_var 语义四层（extern 共存 / 非 extern 覆盖 extern / 双 static
/// 全局允许 / 其余 E3001——O3 零位置照搬）。
test "declare_var_semantics" {
  let tc = TypeChecker::new()
  tc.enter_scope()
  tc.declare_var(
    "x",
    @ast.Type::int(),
    is_global=true,
    is_extern=false,
    is_static=false,
  )
  // 同名重复 → E3001（loc 0:0 照搬 O3 债）
  tc.declare_var(
    "x",
    @ast.Type::int(),
    is_global=true,
    is_extern=false,
    is_static=false,
  )
  assert_eq(tc.errors.length(), 1)
  assert_true(tc.errors[0].code == 3001)
  assert_eq(tc.errors[0].line, 0)
  assert_eq(tc.errors[0].column, 0)
  // extern 声明与既有共存（不报错、不覆盖）
  tc.declare_var(
    "x",
    @ast.Type::int(),
    is_global=true,
    is_extern=true,
    is_static=false,
  )
  assert_eq(tc.errors.length(), 1)
  // 非 extern 定义可替换 extern 声明
  tc.declare_var(
    "y",
    @ast.Type::int(),
    is_global=true,
    is_extern=true,
    is_static=false,
  )
  tc.declare_var(
    "y",
    @ast.Type::double(),
    is_global=true,
    is_extern=false,
    is_static=false,
  )
  assert_eq(tc.errors.length(), 1) // 无新错
  match tc.lookup_var("y") {
    Some(sym) => assert_true(sym.ty is Double(_))
    None => fail("y 应已登记")
  }
  // 双 static 全局（内部链接）允许覆盖
  tc.declare_var(
    "z",
    @ast.Type::int(),
    is_global=true,
    is_extern=false,
    is_static=true,
  )
  tc.declare_var(
    "z",
    @ast.Type::double(),
    is_global=true,
    is_extern=false,
    is_static=true,
  )
  assert_eq(tc.errors.length(), 1)
  // 作用域栈查名：内层遮蔽外层
  tc.declare_var(
    "w",
    @ast.Type::int(),
    is_global=false,
    is_extern=false,
    is_static=false,
  )
  tc.enter_scope()
  tc.declare_var(
    "w",
    @ast.Type::double(),
    is_global=false,
    is_extern=false,
    is_static=false,
  )
  match tc.lookup_var("w") {
    Some(sym) => assert_true(sym.ty is Double(_))
    None => fail("内层 w")
  }
  tc.exit_scope()
  match tc.lookup_var("w") {
    Some(sym) => assert_true(sym.ty is Int(_, _))
    None => fail("外层 w")
  }
}

///|
/// W0-4 char 窄化豁免判据（is_char_safe_initializer：字符常量 / char 值域
/// 内整常量；界外值不豁免）。
test "char_safe_initializer_w0_4" {
  let loc = @source.SourceLoc::new(1, 1)
  // 字符常量（ty=char 的 Literal）
  assert_true(
    is_char_safe_initializer(@ast.Expr::Literal(65, loc, @ast.Type::char())),
  )
  // 值域内整常量（ty=int）
  assert_true(
    is_char_safe_initializer(@ast.Expr::Literal(127, loc, @ast.Type::int())),
  )
  assert_true(
    is_char_safe_initializer(@ast.Expr::Literal(-128, loc, @ast.Type::int())),
  )
  // 界外
  assert_false(
    is_char_safe_initializer(@ast.Expr::Literal(128, loc, @ast.Type::int())),
  )
  assert_false(
    is_char_safe_initializer(@ast.Expr::Literal(1000, loc, @ast.Type::int())),
  )
  // LongLiteral 同域判定
  assert_true(
    is_char_safe_initializer(@ast.Expr::LongLiteral(65L, loc, @ast.Type::int())),
  )
  assert_false(
    is_char_safe_initializer(
      @ast.Expr::LongLiteral(300L, loc, @ast.Type::int()),
    ),
  )
  // 其他表达式形态不豁免
  assert_false(
    is_char_safe_initializer(@ast.Expr::Identifier("x", loc, @ast.Type::int())),
  )
}
