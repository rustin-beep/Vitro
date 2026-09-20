///|
/// T5-b/c call 面白盒锚：check_user_func 四级回退 / visit_call builtin
/// 分派（printf 格式）/ resolve_call_ptr（具名轨 + 函数指针轨 + E3066）/
/// 可变参默认提升。

///|
/// 程序根便捷构造。
fn prog_of(
  funcs : Array[@ast.FuncDecl],
  globals : Array[@ast.GlobalDecl],
) -> @ast.ProgramNode {
  {
    structs: [],
    unions: [],
    globals,
    funcs,
    classes: [],
    templates: [],
    template_instantiations: [],
  }
}

///|
/// 函数声明便捷构造（int 返回 + 单参默认；body 可空 = 存根）。
fn func_of(
  name : String,
  params : Array[@ast.Param],
  body : @ast.Stmt?,
  loc : @source.SourceLoc,
) -> @ast.FuncDecl {
  {
    loc,
    return_type: @ast.Type::int(),
    name,
    params,
    body,
    is_static: false,
    is_extern: false,
    source_file: "t.c",
    is_variadic: false,
  }
}

///|
/// 四级回退：funcs 命中（E3037/E3038）/ static 跨文件 E3058 /
/// bytecode_libc_sig 第四级放行（isdigit 无存根不报 E3036）/ E3036 兜底。
test "call_user_func_four_level_fallback" {
  let loc = @source.SourceLoc::new(3, 5)
  fn param_int(name : String) -> @ast.Param {
    { ty: @ast.Type::int(), name, loc, default: None, }
  }
  // int f(int a) { return a; }
  let f = func_of("f", [param_int("a")], Some(@ast.Stmt::Block([], loc)), loc)
  // static 函数（source_file 与调用点不同文件 → E3058）
  let fs : @ast.FuncDecl = {
    ..func_of("g", [], Some(@ast.Stmt::Block([], loc)), loc),
    is_static: true,
    source_file: "other.c",
  }
  // main：f()（E3037 少参）/ f(&x)（E3038 指针→int）/ g()（E3058）/
  // isdigit(5)（第四级放行无错）/ xyz(1)（E3036）
  fn call(
    name : String,
    arg : @ast.Expr?,
    loc : @source.SourceLoc,
  ) -> @ast.Stmt {
    let args : Array[@ast.Expr] = match arg {
      Some(a) => [a]
      None => []
    }
    @ast.Stmt::Expr(
      @ast.Expr::Call(name, args, loc, @ast.Type::void_type()),
      loc,
    )
  }
  let x_ptr : @ast.Expr = @ast.Expr::Unary(
    Addr,
    @ast.Expr::Identifier("x", loc, @ast.Type::int()),
    loc,
    @ast.Type::void_type(),
  )
  let body : @ast.Stmt = @ast.Stmt::Block(
    [
      @ast.Stmt::VarDecl(@ast.Type::int(), "x", None, [], false, loc),
      call("f", None, loc),
      call("f", Some(x_ptr), loc),
      call("g", Some(@ast.Expr::Literal(1, loc, @ast.Type::int())), loc),
      call("isdigit", Some(@ast.Expr::Literal(5, loc, @ast.Type::int())), loc),
      call("xyz", Some(@ast.Expr::Literal(1, loc, @ast.Type::int())), loc),
    ],
    loc,
  )
  let main = func_of("main", [], Some(body), loc)
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(prog_of([f, fs, main], []))
  assert_eq(errs.length(), 4)
  assert_true(errs[0].code == 3037) // f() 少参
  assert_true(errs[1].code == 3038) // f(&x) 指针→int
  assert_true(errs[2].code == 3058) // static 跨文件
  assert_true(errs[3].code == 3036) // xyz 未定义（isdigit 第四级放行不报）
}

///|
/// visit_call 的 printf builtin 臂：空参 E3030 / 格式-参数错配 E3062 /
/// %s 对 char* 放行。
test "call_printf_builtin_arm" {
  let loc = @source.SourceLoc::new(2, 9)
  fn printf_call(
    args : Array[@ast.Expr],
    loc : @source.SourceLoc,
  ) -> @ast.Stmt {
    @ast.Stmt::Expr(
      @ast.Expr::Call("printf", args, loc, @ast.Type::void_type()),
      loc,
    )
  }
  let fmt_d : @ast.Expr = @ast.Expr::StringLiteral(
    "%d",
    loc,
    @ast.Type::void_type(),
  )
  let fmt_s : @ast.Expr = @ast.Expr::StringLiteral(
    "%s",
    loc,
    @ast.Type::void_type(),
  )
  let str : @ast.Expr = @ast.Expr::StringLiteral(
    "hi",
    loc,
    @ast.Type::void_type(),
  )
  let body : @ast.Stmt = @ast.Stmt::Block(
    [
      printf_call([], loc), // E3030
      printf_call([fmt_d, str], loc), // E3062：%d 对 char*
      printf_call([fmt_s, str], loc), // %s 对字符串字面量——放行
    ],
    loc,
  )
  let main = func_of("main", [], Some(body), loc)
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(prog_of([main], []))
  assert_eq(errs.length(), 2)
  assert_true(errs[0].code == 3030)
  assert_true(errs[1].code == 3062)
}

///|
/// resolve_call_ptr 三轨：具名函数（funcs 命中走 visit_call 定型）/
/// 函数指针轨（参数检查 + 返回类型定型）/ 非函数 E3066。
test "call_ptr_three_tracks" {
  let loc = @source.SourceLoc::new(4, 5)
  // int add(int a) { return a; }
  let add = func_of(
    "add",
    [{ ty: @ast.Type::int(), name: "a", loc, default: None, }],
    Some(@ast.Stmt::Block([], loc)),
    loc,
  )
  // main：int (*fp)(int) = add; int r1 = fp(1); int r2 = add(2);
  //       int q; q(3) —— q 非函数 E3066
  let fp_decl : @ast.Stmt = @ast.Stmt::VarDecl(
    @ast.Type::function_pointer(@ast.Type::int(), [@ast.Type::int()]),
    "fp",
    Some(@ast.Expr::Identifier("add", loc, @ast.Type::void_type())),
    [],
    false,
    loc,
  )
  fn var_init(
    name : String,
    init : @ast.Expr,
    loc : @source.SourceLoc,
  ) -> @ast.Stmt {
    @ast.Stmt::VarDecl(@ast.Type::int(), name, Some(init), [], false, loc)
  }
  let fp_call : @ast.Expr = @ast.Expr::CallPtr(
    @ast.Expr::Identifier("fp", loc, @ast.Type::void_type()),
    [@ast.Expr::Literal(1, loc, @ast.Type::int())],
    loc,
    @ast.Type::void_type(),
  )
  let add_call : @ast.Expr = @ast.Expr::Call(
    "add",
    [@ast.Expr::Literal(2, loc, @ast.Type::int())],
    loc,
    @ast.Type::void_type(),
  )
  let q_call : @ast.Expr = @ast.Expr::CallPtr(
    @ast.Expr::Identifier("q", loc, @ast.Type::void_type()),
    [@ast.Expr::Literal(3, loc, @ast.Type::int())],
    loc,
    @ast.Type::void_type(),
  )
  let body : @ast.Stmt = @ast.Stmt::Block(
    [
      fp_decl,
      var_init("r1", fp_call, loc),
      var_init("r2", add_call, loc),
      @ast.Stmt::VarDecl(@ast.Type::int(), "q", None, [], false, loc),
      @ast.Stmt::Expr(q_call, loc),
    ],
    loc,
  )
  let main = func_of("main", [], Some(body), loc)
  let tc = TypeChecker::new()
  let (typed, errs, _, _) = tc.check(prog_of([add, main], []))
  // fp/add 调用全通过（fp 单层 Pointer(Function)——MoonBit parser F3-v2
  // 语义）；q 非 int 非函数 → 仅 E3066
  assert_eq(errs.length(), 1)
  assert_true(errs[0].code == 3066)
  // fp(1) 定型 int（r1 的 init CallPtr ty）
  match typed.funcs[1].body {
    Some(Block(stmts, _)) =>
      match stmts[1] {
        VarDecl(_, "r1", Some(CallPtr(_, _, _, ty)), _, _, _) =>
          assert_true(ty is Int(_, _))
        _ => fail("r1 应为 CallPtr init")
      }
    _ => fail("main body")
  }
}

///|
/// 可变参数默认提升（C 标准：float→double、char→int——变参尾参走
/// apply_default_argument_promotions，Cast 插入）。
test "call_variadic_default_promotion" {
  let loc = @source.SourceLoc::new(2, 5)
  // int vf(int n, ...)
  let vf : @ast.FuncDecl = {
    ..func_of(
      "vf",
      [{ ty: @ast.Type::int(), name: "n", loc, default: None, }],
      Some(@ast.Stmt::Block([], loc)),
      loc,
    ),
    is_variadic: true,
  }
  let f_lit : @ast.Expr = @ast.Expr::FloatLiteral(1.5, loc, @ast.Type::float())
  let call : @ast.Expr = @ast.Expr::Call(
    "vf",
    [
      @ast.Expr::Literal(1, loc, @ast.Type::int()),
      f_lit, // 变参位 float → 提升 double（FloatLiteral 重定型特例）
    ],
    loc,
    @ast.Type::void_type(),
  )
  let body : @ast.Stmt = @ast.Stmt::Expr(call, loc)
  let main = func_of("main", [], Some(body), loc)
  let tc = TypeChecker::new()
  let (typed, errs, _, _) = tc.check(prog_of([vf, main], []))
  assert_eq(errs.length(), 0)
  match typed.funcs[1].body {
    Some(Expr(Call("vf", args, _, _), _)) =>
      match args[1] {
        FloatLiteral(_, _, ty) => assert_true(ty is Double(_)) // 提升 double，无 Cast 包裹
        _ => fail("变参位 float 应提升为 double（重定型）")
      }
    _ => fail("main body")
  }
}
