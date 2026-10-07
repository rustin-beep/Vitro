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
    ..Default::default(),
    loc,
    return_type: @ast.Type::int(),
    name,
    params,
    body,
    source_file: "t.c",
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
/// visit_call 的 printf builtin 臂：空参 E3030 / 格式-参数错配 W3062（批四降级）/
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
      printf_call([fmt_d, str], loc), // W3062：%d 对 char*
      printf_call([fmt_s, str], loc), // %s 对字符串字面量——放行
    ],
    loc,
  )
  let main = func_of("main", [], Some(body), loc)
  let tc = TypeChecker::new()
  // SEVERITY-FORMAT 销案锚（批四 2026-10-07）：3062 格式-参数类型错配
  // 降 warning（Clang -Wformat 口径）；E3030 空参系参数硬约束维持 error
  let (_, errs, warns, _) = tc.check(prog_of([main], []))
  assert_eq(errs.length(), 1)
  assert_true(errs[0].code == 3030)
  assert_eq(warns.length(), 1)
  assert_true(warns[0].code == 3062)
}

///|
/// %*d 数量臂锚（批四 2026-10-07）：星号 spec 消耗 2 参——
/// `printf("%*d", w, x)` 数量匹配不告警；`printf("%*d", w)` 少 1 参
/// 报 W3032。
test "printf_star_arg_count" {
  let loc = @source.SourceLoc::new(2, 9)
  fn star_call(args : Array[@ast.Expr], loc : @source.SourceLoc) -> @ast.Stmt {
    @ast.Stmt::Expr(
      @ast.Expr::Call(
        "printf",
        [@ast.Expr::StringLiteral("%*d", loc, @ast.Type::void_type()), ..args],
        loc,
        @ast.Type::void_type(),
      ),
      loc,
    )
  }
  fn int_lit(loc : @source.SourceLoc) -> @ast.Expr {
    @ast.Expr::Literal(1, loc, @ast.Type::int())
  }

  let body_ok : @ast.Stmt = @ast.Stmt::Block(
    [star_call([int_lit(loc), int_lit(loc)], loc)],
    loc,
  )
  let main_ok = func_of("main", [], Some(body_ok), loc)
  let tc = TypeChecker::new()
  let (_, errs, warns, _) = tc.check(prog_of([main_ok], []))
  assert_eq(errs.length(), 0)
  assert_eq(warns.length(), 0, msg="%*d 双参数量匹配零告警")
}

///|
/// issue #26：printf/scanf 格式不匹配诊断的**参数序号**（oracle 算式
/// i+2 = 全参数 1-based，参数 1 是格式串——"%f" 配 int 报「第 2 个」）。
/// 此前实现 start+j+2 系统性 +1（报「第 3 个」）；修复 = start+j+1。
test "call_printf_scanf_arg_index_ordinal" {
  let loc = @source.SourceLoc::new(2, 9)
  fn call1(
    name : String,
    fmt : String,
    arg : @ast.Expr,
    loc : @source.SourceLoc,
  ) -> @ast.Stmt {
    @ast.Stmt::Expr(
      @ast.Expr::Call(
        name,
        [@ast.Expr::StringLiteral(fmt, loc, @ast.Type::void_type()), arg],
        loc,
        @ast.Type::void_type(),
      ),
      loc,
    )
  }
  fn int_lit(loc : @source.SourceLoc) -> @ast.Expr {
    @ast.Expr::Literal(1, loc, @ast.Type::int())
  }
  fn dbl_lit(loc : @source.SourceLoc) -> @ast.Expr {
    @ast.Expr::FloatLiteral(1.0, loc, @ast.Type::double())
  }
  // int a; scanf("%d", &a)——double 变量地址（pointee double 不配 %d）
  fn addr_of_d(loc : @source.SourceLoc) -> @ast.Expr {
    @ast.Expr::Unary(
      Addr,
      @ast.Expr::Identifier("d", loc, @ast.Type::double()),
      loc,
      @ast.Type::void_type(),
    )
  }
  let body : @ast.Stmt = @ast.Stmt::Block(
    [
      call1("printf", "%f", int_lit(loc), loc), // W3062：第 2 个参数 'int'
      call1("printf", "%d", dbl_lit(loc), loc), // W3062：第 2 个参数 'double'
      @ast.Stmt::VarDecl(@ast.Type::double(), "d", None, [], false, loc),
      call1("scanf", "%d", addr_of_d(loc), loc), // E3063：第 2 个参数
    ],
    loc,
  )
  let main = func_of("main", [], Some(body), loc)
  let tc = TypeChecker::new()
  // SEVERITY-FORMAT 销案锚（批四 2026-10-07）：3062/3063 全降 warning
  let (_, errs, warns, _) = tc.check(prog_of([main], []))
  assert_eq(errs.length(), 0)
  assert_eq(warns.length(), 3)
  assert_true(warns[0].code == 3062)
  assert_true(
    warns[0].message.contains("第 2 个参数"),
    msg="printf %f 报第 2 个（非第 3）",
  )
  assert_true(warns[1].code == 3062)
  assert_true(
    warns[1].message.contains("第 2 个参数"),
    msg="printf %d 报第 2 个",
  )
  assert_true(warns[2].code == 3063)
  assert_true(
    warns[2].message.contains("第 2 个参数"),
    msg="scanf %d 报第 2 个",
  )
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

///|
test "b3c_undef_func_callptr_single_error" {
  // 审阅 P2-3（2026-10-07）：#8 的锚必须走 **CallPtr**（C 输入实际形态
  //——parser 后缀位统一产 CallPtr，Expr::Call 仅 C++ ctor 不可达；旧锚
  // 手写 Expr::Call 走 resolve_call 对新分支零判别）。反锚：E3036 单错
  //（无 E3014 级联——第四级返 int 兜底）+ 已声明变量调用仍 E3066
  let loc = @source.SourceLoc::new(2, 5)
  let call_undef : @ast.Expr = @ast.Expr::CallPtr(
    @ast.Expr::Identifier("foo", loc, @ast.Type::void_type()),
    [@ast.Expr::Literal(1, loc, @ast.Type::int())],
    loc,
    @ast.Type::void_type(),
  )
  let ret : @ast.Stmt = @ast.Stmt::Return(Some(call_undef), loc)
  let main = func_of("main", [], Some(@ast.Stmt::Block([ret], loc)), loc)
  let tc = TypeChecker::new()
  let (typed, errs, _, _) = tc.check(prog_of([main], []))
  assert_eq(errs.length(), 1, msg="E3036 单错（无 E3014 级联）")
  assert_true(errs[0].code == 3036)
  // return 语句类型不匹配不再出现（int 兜底 == main 的 int 返回）
  match typed.funcs[0].body {
    Some(Block(stmts, _)) =>
      if stmts.length() > 0 {
        match stmts[stmts.length() - 1] {
          Return(Some(CallPtr(_, _, _, rty)), _) =>
            assert_true(
              rty.kind() is TK_Int,
              msg="调用定型 int（隐式 int 口径）",
            )
          _ => fail("形态不符: 末语句非 Return")
        }
      } else {
        fail("形态不符: 空块")
      }
    _ => fail("形态不符: body 非 Block")
  }
}
