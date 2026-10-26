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
  // #214：仅 Block 体且尾语句非 Return 时兜底补 return 0——W3084 对无
  // return 构造体全面触发，各测试断言面在调用/格式诊断；直 body / 尾
  // 已 Return 的构造（Return 语义与形态断言测试）原样不动
  let body = match body {
    Some(@ast.Stmt::Block(stmts, bloc)) => {
      let tail_is_return = stmts.length() > 0 &&
        stmts[stmts.length() - 1] is @ast.Stmt::Return(_, _)
      if tail_is_return {
        body
      } else {
        Some(
          @ast.Stmt::Block(
            {
              let all : Array[@ast.Stmt] = []
              for st in stmts {
                all.push(st)
              }
              all.push(
                @ast.Stmt::Return(
                  Some(@ast.Expr::Literal(0, loc, @ast.Type::int())),
                  loc,
                ),
              )
              all
            },
            bloc,
          ),
        )
      }
    }
    _ => body
  }
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
      @ast.Stmt::VarDecl(@ast.Type::int(), "x", None, [], false, false, loc),
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
/// #159（2026-10-26）：printf 星号精度位的实参 Member 须定型回写——
/// `printf("%.*s", p.bbb, s)` 的 p.bbb 在星号参数槽（非值参数槽），
/// 旧「粗放行不查类型」连 resolve 也跳过：Member 的 object 保持 Void
/// 占位 → codegen get_member_offset(Void) 落 `_ => 0` → 字段偏移静默
/// 丢失（p.bbb 读成 p.aaa——回文 len=1 病根）。同族先例：sscanf 尾参
/// 零回写（#161，见 sscanf_variadic_tail_member_typed）。本锚断言
/// 定型树里星号槽 args[1] 的 Member(object=p) ty 回写为 struct P。
test "printf_star_member_typed" {
  let loc = @source.SourceLoc::new(5, 5)
  // struct P { int aaa; int bbb; };
  let p_decl : @ast.StructDecl = {
    ..Default::default(),
    loc,
    name: "P",
    fields: [
      { ty: @ast.Type::int(), name: "aaa", },
      { ty: @ast.Type::int(), name: "bbb", },
    ],
  }
  // p.bbb：object 故意给 Void 占位（parser 初值形态——定型回写是被测面）
  let p_bbb : @ast.Expr = @ast.Expr::Member(
    @ast.Expr::Identifier("p", loc, @ast.Type::void_type()),
    "bbb",
    false,
    loc,
    @ast.Type::void_type(),
  )
  let printf_call : @ast.Expr = @ast.Expr::CallPtr(
    @ast.Expr::Identifier("printf", loc, @ast.Type::void_type()),
    [
      @ast.Expr::StringLiteral("%.*s", loc, @ast.Type::void_type()),
      p_bbb,
      @ast.Expr::StringLiteral("x", loc, @ast.Type::void_type()),
    ],
    loc,
    @ast.Type::void_type(),
  )
  // main：P p; printf("%.*s", p.bbb, "x");
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc,
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(
      @ast.Stmt::Block(
        [
          @ast.Stmt::VarDecl(
            @ast.Type::struct_type("P"),
            "p",
            None,
            [],
            false,
            false,
            loc,
          ),
          @ast.Stmt::Expr(printf_call, loc),
        ],
        loc,
      ),
    ),
    source_file: "t.c",
  }
  let tc = TypeChecker::new()
  let (typed, errs, _, _) = tc.check({
    structs: [p_decl],
    unions: [],
    globals: [],
    funcs: [main],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_eq(errs.filter(e => e.code >= 3000 && e.code < 4000).length(), 0)
  guard typed.funcs[0].body is Some(@ast.Stmt::Block(stmts, _)) else {
    fail("main body 缺失")
  }
  guard stmts[1] is @ast.Stmt::Expr(@ast.Expr::CallPtr(_, args, _, _), _) else {
    fail("printf 调用语句形态不符")
  }
  guard args[1] is @ast.Expr::Member(object, "bbb", _, _, _) else {
    fail("args[1] 非 p.bbb 形态")
  }
  // 核心断言：object（p）的 ty 已回写为 struct P（旧缺口 = Void）
  assert_true(
    object.ty().kind() is TK_Struct && object.ty().name() == "P",
    msg="printf 星号槽 p.bbb 的 Member object 须定型为 struct P（#159：旧零回写留 Void → 字段偏移静默丢）",
  )
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
      @ast.Stmt::VarDecl(@ast.Type::double(), "d", None, [], false, false, loc),
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
    false,
    loc,
  )
  fn var_init(
    name : String,
    init : @ast.Expr,
    loc : @source.SourceLoc,
  ) -> @ast.Stmt {
    @ast.Stmt::VarDecl(
      @ast.Type::int(),
      name,
      Some(init),
      [],
      false,
      false,
      loc,
    )
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
      @ast.Stmt::VarDecl(@ast.Type::int(), "q", None, [], false, false, loc),
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
        VarDecl(_, "r1", Some(CallPtr(_, _, _, ty)), _, _, _, _) =>
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

///|
/// 病 11 两层收编的**错误支路文案锚**（审阅处置 2026-10-10 P3-1）：表驱动
/// 臂（check_builtin_table @libc.sig_of）此前合法路径有 typeck_diff hash 锁、
/// 错误支路文案零覆盖——实测改 count/D 位文案 moon test 35/35 全绿。本测试
/// 锁三类形态：count 文案（第二层收编中文数字→阿拉伯数字）、math D 位带
/// 位号文案（单参旧文案无位号已统一）、P 位文案（builtin_check_pointer 单源）。
test "builtin_table_error_path_copy_anchor" {
  let loc = @source.SourceLoc::new(2, 9)
  fn call(
    name : String,
    args : Array[@ast.Expr],
    loc : @source.SourceLoc,
  ) -> @ast.Stmt {
    @ast.Stmt::Expr(
      @ast.Expr::Call(name, args, loc, @ast.Type::void_type()),
      loc,
    )
  }
  fn str_lit(loc : @source.SourceLoc) -> @ast.Expr {
    @ast.Expr::StringLiteral("hi", loc, @ast.Type::void_type())
  }
  fn dbl_lit(loc : @source.SourceLoc) -> @ast.Expr {
    @ast.Expr::FloatLiteral(1.0, loc, @ast.Type::double())
  }
  fn int_lit(loc : @source.SourceLoc) -> @ast.Expr {
    @ast.Expr::Literal(1, loc, @ast.Type::int())
  }
  let body : @ast.Stmt = @ast.Stmt::Block(
    [
      call("strchr", [str_lit(loc)], loc), // E3028：count 少参
      call("fmod", [dbl_lit(loc)], loc), // E3028：count 少参（math 族）
      call("tan", [str_lit(loc)], loc), // E3029：D 位类型错
      call("strlen", [int_lit(loc)], loc), // E3029：P 位类型错
    ],
    loc,
  )
  let main = func_of("main", [], Some(body), loc)
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check(prog_of([main], []))
  assert_eq(errs.length(), 4)
  assert_true(errs[0].code == 3028)
  assert_true(
    errs[0].message.contains("strchr 需要2个参数"),
    msg="count 文案（strchr——中文数字→阿拉伯数字随第二层收编统一）",
  )
  assert_true(errs[1].code == 3028)
  assert_true(
    errs[1].message.contains("fmod 需要2个参数"),
    msg="count 文案（fmod）",
  )
  assert_true(errs[2].code == 3029)
  assert_true(
    errs[2].message.contains("tan 第 1 个参数必须是 double"),
    msg="D 位带位号文案（单参旧文案无位号已统一）",
  )
  assert_true(errs[3].code == 3029)
  assert_true(
    errs[3].message.contains(
      "strlen 的第 1 个参数必须是指针或数组",
    ),
    msg="P 位文案（builtin_check_pointer 单源复用）",
  )
}

///|
/// 病 15 批 A 红→绿锚（FILE* 位三态判定；批 A' 随病 15 收尾收紧）：
/// int 一律报 W3068（批 A 初版曾放行字面量 0/1/2——宏体 cast 化后裸常量
/// 无宏来源即收）；指针放行；非指针非 int 维持 E3029；
/// fflush 补专臂（此前经存根签名检查——`fflush(stdout)` 展开后误吃 E3054）。
test "file_pointer_arg_three_state_anchor" {
  let loc = @source.SourceLoc::new(2, 9)
  fn call(
    name : String,
    args : Array[@ast.Expr],
    loc : @source.SourceLoc,
  ) -> @ast.Expr {
    @ast.Expr::Call(name, args, loc, @ast.Type::void_type())
  }
  fn int_lit(v : Int32, loc : @source.SourceLoc) -> @ast.Expr {
    @ast.Expr::Literal(v, loc, @ast.Type::int())
  }
  fn dbl_lit(loc : @source.SourceLoc) -> @ast.Expr {
    @ast.Expr::FloatLiteral(1.5, loc, @ast.Type::double())
  }
  fn bad_var_decl(loc : @source.SourceLoc) -> @ast.Stmt {
    @ast.Stmt::VarDecl(@ast.Type::int(), "bad", None, [], false, false, loc)
  }
  fn bad_var(loc : @source.SourceLoc) -> @ast.Expr {
    @ast.Expr::Identifier("bad", loc, @ast.Type::void_type())
  }
  fn expr_stmt(e : @ast.Expr, loc : @source.SourceLoc) -> @ast.Stmt {
    @ast.Stmt::Expr(e, loc)
  }
  fn run(
    stmts : Array[@ast.Stmt],
    loc : @source.SourceLoc,
  ) -> (Array[TypeError], Array[TypeError]) {
    let body : @ast.Stmt = @ast.Stmt::Block(stmts, loc)
    let main = func_of("main", [], Some(body), loc)
    let tc = TypeChecker::new()
    let (_, errs, warns, _) = tc.check(prog_of([main], []))
    (errs, warns)
  }
  // ① 裸字面量 1 报 W3068（批 A' 收紧锚，随病 15 收尾：宏体 cast 化后
  // 裸常量无宏来源——stdout 现展开为 ((FILE *)1) 走指针分支零诊断，
  // 由 lexer 锚 stdio_macro_cast_body_expansion 锁定）
  let (e1, w1) = run(
    [
      expr_stmt(
        call("fseek", [int_lit(1, loc), int_lit(0, loc), int_lit(0, loc)], loc),
        loc,
      ),
    ],
    loc,
  )
  assert_eq(
    e1.length(),
    0,
    msg="裸 int（含 0/1/2 字面量）不报错只报 W",
  )
  assert_eq(
    w1.length(),
    1,
    msg="裸字面量 1 报 W3068（批 A' 收紧锚）",
  )
  assert_true(w1[0].code == 3068)
  // ② 裸字面量 7：W3068（当前零诊断——红锚）
  let (e2, w2) = run(
    [
      expr_stmt(
        call("fseek", [int_lit(7, loc), int_lit(0, loc), int_lit(0, loc)], loc),
        loc,
      ),
    ],
    loc,
  )
  assert_eq(e2.length(), 0, msg="非常量 int 不报错只报 W")
  assert_eq(w2.length(), 1, msg="裸字面量 7 报一条 W3068")
  assert_true(w2[0].code == 3068, msg="W3068 码位")
  assert_true(
    w2[0].message.contains("文件指针"),
    msg="W3068 文案指向 FILE*",
  )
  // ③ int 变量：W3068（当前零诊断——红锚）
  let (e3, w3) = run(
    [
      bad_var_decl(loc),
      expr_stmt(
        call("fseek", [bad_var(loc), int_lit(0, loc), int_lit(0, loc)], loc),
        loc,
      ),
    ],
    loc,
  )
  assert_eq(e3.length(), 0)
  assert_eq(w3.length(), 1, msg="int 变量传 FILE* 位报 W3068")
  assert_true(w3[0].code == 3068)
  // ④ fflush(裸 1) 与 ① 同收紧（批 A'：W3068；真 stdout 走指针分支零诊断）
  let (e4, w4) = run(
    [expr_stmt(call("fflush", [int_lit(1, loc)], loc), loc)],
    loc,
  )
  assert_eq(
    e4.length(),
    0,
    msg="fflush 专臂不报错（原 E3054 误拦已修）",
  )
  assert_eq(w4.length(), 1, msg="裸 1 报 W3068（批 A' 收紧）")
  // ⑤ fflush(int 变量)：W3068
  let (e5, w5) = run(
    [bad_var_decl(loc), expr_stmt(call("fflush", [bad_var(loc)], loc), loc)],
    loc,
  )
  assert_eq(e5.length(), 0)
  assert_eq(w5.length(), 1, msg="fflush int 变量报 W3068")
  assert_true(w5[0].code == 3068)
  // ⑥ 非指针非 int（double）维持 E3029（回归锚）
  let (e6, w6) = run(
    [
      expr_stmt(
        call("fseek", [dbl_lit(loc), int_lit(0, loc), int_lit(0, loc)], loc),
        loc,
      ),
    ],
    loc,
  )
  assert_eq(e6.length(), 1, msg="double 传 FILE* 位维持 E3029")
  assert_true(e6[0].code == 3029)
  assert_eq(w6.length(), 0)
}

///|
/// #79（2026-10-13 报 / 2026-10-14 修）：`print_int` 保留名劫持——
/// visit_call 对 print_int 无条件走内置签名检查（print_int(int)），用户
/// 重定义被静默无视：正确调用自有 print_int(int\*) 被误拒 E3029、传参
/// 类型不匹配（int 给 int\*）被零诊断误收。修复对齐 qsort 先例（funcs
/// 命中用户定义优先 check_user_func）；__vitro_\* 内部名不适用（用户不
/// 会定义双下划线名）。
test "issue79_print_int_user_redefine_priority" {
  let loc = @source.SourceLoc::new(3, 5)
  // ① 用户签名（int\* 形参）正确调用（取址实参）：零诊断（旧 E3029 误拒）
  let tc = TypeChecker::new()
  tc.enter_scope()
  tc.declare_var(
    "v",
    @ast.Type::int(),
    is_global=false,
    is_extern=false,
    is_static=false,
  )
  tc.funcs.set("print_int", {
    return_type: @ast.Type::void_type(),
    param_types: [@ast.Type::Pointer(@ast.Type::int(), false)],
    is_variadic: false,
    param_defaults: [None],
    is_definition: true,
    first_decl_line: 1,
  })
  let addr_of_v = @ast.Expr::Unary(
    @ast.UnaryOp::Addr,
    @ast.Expr::Identifier("v", loc, @ast.Type::int()),
    loc,
    @ast.Type::Pointer(@ast.Type::int(), false),
  )
  let args1 : Array[@ast.Expr] = [addr_of_v]
  ignore(tc.visit_call("print_int", args1, loc))
  inspect(tc.errors.length(), content="0")
  // ② 用户签名错误调用（int 实参给 int\* 形参）：E3054（旧零诊断误收）
  let tc2 = TypeChecker::new()
  tc2.funcs.set("print_int", {
    return_type: @ast.Type::void_type(),
    param_types: [@ast.Type::Pointer(@ast.Type::int(), false)],
    is_variadic: false,
    param_defaults: [None],
    is_definition: true,
    first_decl_line: 1,
  })
  let args2 : Array[@ast.Expr] = [@ast.Expr::Literal(42, loc, @ast.Type::int())]
  ignore(tc2.visit_call("print_int", args2, loc))
  inspect(tc2.errors.length(), content="1")
  inspect(tc2.errors[0].code, content="3054")
  // ③ 反例锚：无用户定义时内置签名照旧（print_int(int) 收 int 实参）
  let tc3 = TypeChecker::new()
  let args3 : Array[@ast.Expr] = [@ast.Expr::Literal(7, loc, @ast.Type::int())]
  ignore(tc3.visit_call("print_int", args3, loc))
  inspect(tc3.errors.length(), content="0")
}

///|
/// #161（2026-10-18）：sscanf 变参尾参定型缺口——check_builtin_sscanf
/// 旧只查前两参，尾参（&r.cls 形态的 Addr(Member)）零 resolve 零回写，
/// Member 的 object 保持 Void 占位（codegen 取址 get_member_offset 按
/// object.ty 判型 → Void 落 0 → 成员偏移丢失、sscanf 写偏基址）。
/// 修复后尾参逐参 resolve 回写——本锚断言定型树里 args[2] 的
/// Member(object=r) 的 ty 被回写为 struct Row。
test "sscanf_variadic_tail_member_typed" {
  let loc = @source.SourceLoc::new(5, 5)
  // struct Row { int id; char cls; };
  let row : @ast.StructDecl = {
    ..Default::default(),
    loc,
    name: "Row",
    fields: [
      { ty: @ast.Type::int(), name: "id", },
      { ty: @ast.Type::char(), name: "cls", },
    ],
  }
  // &r.cls：object 故意给 Void 占位（parser 初值形态——定型回写是本锚被测面）
  let addr_of_cls : @ast.Expr = @ast.Expr::Unary(
    @ast.UnaryOp::Addr,
    @ast.Expr::Member(
      @ast.Expr::Identifier("r", loc, @ast.Type::void_type()),
      "cls",
      false,
      loc,
      @ast.Type::void_type(),
    ),
    loc,
    @ast.Type::void_type(),
  )
  let sscanf_call : @ast.Expr = @ast.Expr::CallPtr(
    @ast.Expr::Identifier("sscanf", loc, @ast.Type::void_type()),
    [
      @ast.Expr::StringLiteral("A", loc, @ast.Type::void_type()),
      @ast.Expr::StringLiteral("%c", loc, @ast.Type::void_type()),
      addr_of_cls,
    ],
    loc,
    @ast.Type::void_type(),
  )
  // main：Row r; sscanf("A", "%c", &r.cls);
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc,
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(
      @ast.Stmt::Block(
        [
          @ast.Stmt::VarDecl(
            @ast.Type::struct_type("Row"),
            "r",
            None,
            [],
            false,
            false,
            loc,
          ),
          @ast.Stmt::Expr(sscanf_call, loc),
        ],
        loc,
      ),
    ),
    source_file: "t.c",
  }
  let tc = TypeChecker::new()
  let (typed, errs, _, _) = tc.check({
    structs: [row],
    unions: [],
    globals: [],
    funcs: [main],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_eq(errs.filter(e => e.code >= 3000 && e.code < 4000).length(), 0)
  // 定型树回查：main 体里 sscanf 调用 args[2] = Unary(Addr, Member(object=r))
  guard typed.funcs[0].body is Some(@ast.Stmt::Block(stmts, _)) else {
    fail("main body 缺失")
  }
  guard stmts[1] is @ast.Stmt::Expr(@ast.Expr::CallPtr(_, args, _, _), _) else {
    fail("sscanf 调用语句形态不符")
  }
  guard args[2]
    is @ast.Expr::Unary(
      @ast.UnaryOp::Addr,
      @ast.Expr::Member(object, "cls", _, _, _),
      _,
      _
    ) else {
    fail("args[2] 非 &r.cls 形态")
  }
  // 核心断言：object（r）的 ty 已回写为 struct Row（旧缺口 = Void）
  assert_true(
    object.ty().kind() is TK_Struct && object.ty().name() == "Row",
    msg="sscanf 尾参 &r.cls 的 Member object 须定型为 struct Row（#161：旧零回写留 Void → 取址偏移丢失）",
  )
}

///|
/// #161 补锚（2026-10-18 审阅批 P3-3）：sscanf 双路径的**非字面量 fmt**
/// 分支——fmt 为变量时走逐参 resolve 回写 + 非指针 W3035 口径。突变
/// no-op 化该循环（resolve 不回写）后此锚立红（字面量锚不覆盖此分支）。
test "sscanf_nonliteral_fmt_tail_args_resolved" {
  let loc = @source.SourceLoc::new(5, 5)
  let row : @ast.StructDecl = {
    ..Default::default(),
    loc,
    name: "Row",
    fields: [
      { ty: @ast.Type::int(), name: "id", },
      { ty: @ast.Type::char(), name: "cls", },
    ],
  }
  let addr_of_cls : @ast.Expr = @ast.Expr::Unary(
    @ast.UnaryOp::Addr,
    @ast.Expr::Member(
      @ast.Expr::Identifier("r", loc, @ast.Type::void_type()),
      "cls",
      false,
      loc,
      @ast.Type::void_type(),
    ),
    loc,
    @ast.Type::void_type(),
  )
  // fmt 是局部 char 数组变量（非字面量 → else 分支逐参 resolve）
  let sscanf_call : @ast.Expr = @ast.Expr::CallPtr(
    @ast.Expr::Identifier("sscanf", loc, @ast.Type::void_type()),
    [
      @ast.Expr::Identifier(
        "src",
        loc,
        @ast.Type::array_of(@ast.Type::char(), [4]),
      ),
      @ast.Expr::Identifier(
        "fmt",
        loc,
        @ast.Type::array_of(@ast.Type::char(), [4]),
      ),
      addr_of_cls,
    ],
    loc,
    @ast.Type::void_type(),
  )
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc,
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(
      @ast.Stmt::Block(
        [
          @ast.Stmt::VarDecl(
            @ast.Type::struct_type("Row"),
            "r",
            None,
            [],
            false,
            false,
            loc,
          ),
          @ast.Stmt::VarDecl(
            @ast.Type::array_of(@ast.Type::char(), [4]),
            "fmt",
            None,
            [],
            false,
            false,
            loc,
          ),
          @ast.Stmt::VarDecl(
            @ast.Type::array_of(@ast.Type::char(), [4]),
            "src",
            None,
            [],
            false,
            false,
            loc,
          ),
          @ast.Stmt::Expr(sscanf_call, loc),
        ],
        loc,
      ),
    ),
    source_file: "t.c",
  }
  let tc = TypeChecker::new()
  let (typed, errs, _, _) = tc.check({
    structs: [row],
    unions: [],
    globals: [],
    funcs: [main],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_eq(errs.length(), 0)
  guard typed.funcs[0].body is Some(@ast.Stmt::Block(stmts, _)) else {
    fail("main body 缺失")
  }
  guard stmts[3] is @ast.Stmt::Expr(@ast.Expr::CallPtr(_, args, _, _), _) else {
    fail("sscanf 调用语句形态不符")
  }
  guard args[2]
    is @ast.Expr::Unary(
      @ast.UnaryOp::Addr,
      @ast.Expr::Member(object, "cls", _, _, _),
      _,
      _
    ) else {
    fail("args[2] 非 &r.cls 形态")
  }
  assert_true(
    object.ty().kind() is TK_Struct && object.ty().name() == "Row",
    msg="非字面量 fmt 分支的尾参 &r.cls 须回写定型（#161 else 分支）",
  )
}

///|
/// #197（2026-10-21）：snprintf/sprintf 变参尾参 resolve 回写——旧只查
/// 前 2/3 参，尾参 Member 保持 parser Void 占位，codegen 按 object.ty
/// 判型落 0 读垃圾（`snprintf(buf,n,"%.2f",a->b)` 的成员值变地址）。
/// 红锚：修复前尾参 expr 保持 Void 占位（ty 非 Double）；修后 resolve
/// 回写定型。#161（sscanf 尾参）同族——printf 族两兄弟当年漏连坐。
test "snprintf_sprintf_tail_args_resolved_issue197" {
  let loc = @source.SourceLoc::new(2, 9)
  let tc = TypeChecker::new()
  tc.enter_scope()
  tc.structs.set("A", {
    fields: [(@ast.Type::double(), "b")],
    is_complete: true,
  })
  tc.declare_var(
    "a",
    @ast.Type::Pointer(@ast.Type::struct_type("A"), false),
    is_global=false,
    is_extern=false,
    is_static=false,
  )
  tc.declare_var(
    "buf",
    @ast.Type::pointer_to(@ast.Type::char()),
    is_global=false,
    is_extern=false,
    is_static=false,
  )
  // a->b（未 resolve 形态——object/ty 均 Void 占位）
  fn raw_member(loc : @source.SourceLoc) -> @ast.Expr {
    @ast.Expr::Member(
      @ast.Expr::Identifier("a", loc, @ast.Type::void_type()),
      "b",
      true,
      loc,
      @ast.Type::void_type(),
    )
  }
  // snprintf(buf, 64, "%.2f", a->b)
  let call1 = @ast.Expr::Call(
    "snprintf",
    [
      @ast.Expr::Identifier("buf", loc, @ast.Type::void_type()),
      @ast.Expr::Literal(64, loc, @ast.Type::int()),
      @ast.Expr::StringLiteral("%.2f", loc, @ast.Type::void_type()),
      raw_member(loc),
    ],
    loc,
    @ast.Type::void_type(),
  )
  let _ = tc.resolve_expr_type(call1)
  match call1 {
    Call(_, args, _, _) =>
      match args[3] {
        Member(_, _, _, _, mty) =>
          assert_true(
            mty.kind() is TK_Double,
            msg="snprintf 尾参 a->b 须 resolve 定型 double（实得 \{mty.to_c_string()}）",
          )
        _ => fail("尾参形态坏")
      }
    _ => fail("调用形态坏")
  }
  assert_eq(tc.errors.length(), 0, msg="合法调用零诊断")
  // sprintf(buf, "%d", a->b)——b 是 double 对 %d：W3062 对位警告（不 error）
  let tc2 = TypeChecker::new()
  tc2.enter_scope()
  tc2.structs.set("A", { fields: [(@ast.Type::int(), "n")], is_complete: true, })
  tc2.declare_var(
    "a",
    @ast.Type::Pointer(@ast.Type::struct_type("A"), false),
    is_global=false,
    is_extern=false,
    is_static=false,
  )
  tc2.declare_var(
    "buf",
    @ast.Type::pointer_to(@ast.Type::char()),
    is_global=false,
    is_extern=false,
    is_static=false,
  )
  let call2 = @ast.Expr::Call(
    "sprintf",
    [
      @ast.Expr::Identifier("buf", loc, @ast.Type::void_type()),
      @ast.Expr::StringLiteral("%d", loc, @ast.Type::void_type()),
      @ast.Expr::Member(
        @ast.Expr::Identifier("a", loc, @ast.Type::void_type()),
        "n",
        true,
        loc,
        @ast.Type::void_type(),
      ),
    ],
    loc,
    @ast.Type::void_type(),
  )
  let _ = tc2.resolve_expr_type(call2)
  match call2 {
    Call(_, args, _, _) =>
      match args[2] {
        Member(_, _, _, _, mty) =>
          assert_true(
            mty.kind() is TK_Int,
            msg="sprintf 尾参 a->n 须 resolve 定型 int（实得 \{mty.to_c_string()}）",
          )
        _ => fail("尾参形态坏")
      }
    _ => fail("调用形态坏")
  }
  assert_eq(tc2.errors.length(), 0)
}
