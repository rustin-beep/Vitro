///|
/// #433 批 B9 剩余形态红锚入库（2026-11-12 第三批）：本文件锚在**修前
/// 代码**下必红（缺陷实锤，J9 证红义务），随本批处方落地转绿——转绿后
/// 即为回归锚。覆盖：M10c-A-4（builtin 函数指针位放行 int）/ M09-A5
/// （W3085 跨文件假阳性）/ M05-A1+A-2 连坐（typeof 丢 const）/ M05-A3
/// （typeof 带初始化器 auto 式）/ M05-A4（union/struct 同名 tag 误收）/
/// M09 P3 散件（A8 designator / C1 Label / C2 参数重定义位置 / C4 自引用
/// / C6 W3008 文案）。探针 CLI 实录见 tmp/batch/i433_REPORT.md。

///|
/// 红锚 A4-a（P1）：qsort compar 位传 int 字面量 7——修前判据
/// `!(TK_Int) && !(TK_Pointer)` 显式放行 int ⇒ 零诊断误收（M10c-A-4；
/// clang/gcc/WSL 双真值均 error 级——incompatible integer to pointer
/// conversion）。修后应报 E3029「必须是函数指针」。
test "m10c_red_qsort_compar_int_accepted" {
  let loc = @source.SourceLoc::new(3, 3)
  let arr_decl : @ast.Stmt = @ast.Stmt::VarDecl(
    @ast.Type::array_of(@ast.Type::int(), [2]),
    "arr",
    None,
    [],
    false,
    false,
    loc,
  )
  let qsort_call : @ast.Stmt = @ast.Stmt::Expr(
    @ast.Expr::CallPtr(
      @ast.Expr::Identifier("qsort", loc, @ast.Type::void_type()),
      [
        @ast.Expr::Identifier("arr", loc, @ast.Type::void_type()),
        @ast.Expr::Literal(2, loc, @ast.Type::int()),
        @ast.Expr::Literal(4, loc, @ast.Type::int()),
        @ast.Expr::Literal(7, loc, @ast.Type::int()),
      ],
      loc,
      @ast.Type::void_type(),
    ),
    loc,
  )
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc,
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(@ast.Stmt::Block([arr_decl, qsort_call], loc)),
    source_file: "t.c",
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check({
    structs: [],
    unions: [],
    globals: [],
    funcs: [main],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_true(
    errs.exists(e => e.code == 3029),
    msg="qsort compar 位传 int 7 应报 E3029（实得 \{errs.length()} 条 error：\{errs.map(e => e.code.to_string()).join(",")}）",
  )
}

///|
/// 红锚 A4-b（P1）：bsearch compar 位传 int 字面量 7——同 A4-a 根因
/// （M10c-A-4；include 形态专臂拦截导致与 qsort 的 E3054 同判面分叉）。
test "m10c_red_bsearch_compar_int_accepted" {
  let loc = @source.SourceLoc::new(3, 3)
  let arr_decl : @ast.Stmt = @ast.Stmt::VarDecl(
    @ast.Type::array_of(@ast.Type::int(), [2]),
    "arr",
    None,
    [],
    false,
    false,
    loc,
  )
  let bsearch_call : @ast.Stmt = @ast.Stmt::Expr(
    @ast.Expr::CallPtr(
      @ast.Expr::Identifier("bsearch", loc, @ast.Type::void_type()),
      [
        @ast.Expr::Identifier("arr", loc, @ast.Type::void_type()),
        @ast.Expr::Identifier("arr", loc, @ast.Type::void_type()),
        @ast.Expr::Literal(2, loc, @ast.Type::int()),
        @ast.Expr::Literal(4, loc, @ast.Type::int()),
        @ast.Expr::Literal(7, loc, @ast.Type::int()),
      ],
      loc,
      @ast.Type::void_type(),
    ),
    loc,
  )
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc,
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(@ast.Stmt::Block([arr_decl, bsearch_call], loc)),
    source_file: "t.c",
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check({
    structs: [],
    unions: [],
    globals: [],
    funcs: [main],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_true(
    errs.exists(e => e.code == 3029),
    msg="bsearch compar 位传 int 7 应报 E3029（实得 \{errs.length()} 条 error：\{errs.map(e => e.code.to_string()).join(",")}）",
  )
}

///|
/// 红锚 A4-c（P1）：realloc 首参传 int 字面量 5——修前判据显式放行 int ⇒
/// typeck 零诊断（运行期 E3027 deny 兜底，教学体验=先过编译再被拦；
/// M10c-A-4；三方编译期 error）。
test "m10c_red_realloc_first_arg_int_accepted" {
  let loc = @source.SourceLoc::new(2, 3)
  let realloc_call : @ast.Stmt = @ast.Stmt::Expr(
    @ast.Expr::CallPtr(
      @ast.Expr::Identifier("realloc", loc, @ast.Type::void_type()),
      [
        @ast.Expr::Literal(5, loc, @ast.Type::int()),
        @ast.Expr::Literal(10, loc, @ast.Type::int()),
      ],
      loc,
      @ast.Type::void_type(),
    ),
    loc,
  )
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc,
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(@ast.Stmt::Block([realloc_call], loc)),
    source_file: "t.c",
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check({
    structs: [],
    unions: [],
    globals: [],
    funcs: [main],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_true(
    errs.exists(e => e.code == 3029),
    msg="realloc 首参传 int 5 应报 E3029（实得 \{errs.length()} 条 error：\{errs.map(e => e.code.to_string()).join(",")}）",
  )
}

///|
/// 锚 A4-反向（防收紧误伤）：裸字面量 0 是 null pointer constant——
/// `qsort(..., 0)` / `realloc(0, n)` clang 零诊断（实测），修后判据须
/// 放行（NULL 经词法层已是指针形态走 TK_Pointer，本锚覆盖裸 0 面）。
test "m10c_anchor_zero_literal_null_pointer_constant_passes" {
  let loc = @source.SourceLoc::new(2, 3)
  let arr_decl : @ast.Stmt = @ast.Stmt::VarDecl(
    @ast.Type::array_of(@ast.Type::int(), [2]),
    "arr",
    None,
    [],
    false,
    false,
    loc,
  )
  let qsort_zero : @ast.Stmt = @ast.Stmt::Expr(
    @ast.Expr::CallPtr(
      @ast.Expr::Identifier("qsort", loc, @ast.Type::void_type()),
      [
        @ast.Expr::Identifier("arr", loc, @ast.Type::void_type()),
        @ast.Expr::Literal(2, loc, @ast.Type::int()),
        @ast.Expr::Literal(4, loc, @ast.Type::int()),
        @ast.Expr::Literal(0, loc, @ast.Type::int()),
      ],
      loc,
      @ast.Type::void_type(),
    ),
    loc,
  )
  let realloc_zero : @ast.Stmt = @ast.Stmt::Expr(
    @ast.Expr::CallPtr(
      @ast.Expr::Identifier("realloc", loc, @ast.Type::void_type()),
      [
        @ast.Expr::Literal(0, loc, @ast.Type::int()),
        @ast.Expr::Literal(10, loc, @ast.Type::int()),
      ],
      loc,
      @ast.Type::void_type(),
    ),
    loc,
  )
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc,
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(@ast.Stmt::Block([arr_decl, qsort_zero, realloc_zero], loc)),
    source_file: "t.c",
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check({
    structs: [],
    unions: [],
    globals: [],
    funcs: [main],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_false(
    errs.exists(e => e.code == 3029),
    msg="裸 0 = null pointer constant 不得报 E3029（实得 \{errs.map(e => e.code.to_string()).join(",")}）",
  )
}

///|
/// 红锚 A5（P2）：W3085 跨文件拼接序假阳性——调用文件（main_b.c）拼接
/// 在前、定义文件（lib_a2.c）在后时，修前判据 `loc.line <
/// sym.first_decl_line` 无文件过滤，报 W3085 且文案行号（拼接序）指向
/// **另一个文件**的首声明（M09-A5；探针 P6，clang/gcc 分文件编译无此
/// 形态）。修后按 file_boundaries 判「调用行与首声明行同文件」，跨文件
/// 不判行号序。**file_boundaries 由 gateway merge_units 的 file_ranges
/// 直通**（真实管线形态——api compile files 拼接单源，parser 不写
/// FuncDecl.source_file，按 source_file 判恒同值不可用；本锚按真实
/// 机制手搭边界表）。反向锚：同文件前向照报（门只挡跨文件）。
test "m09_red_w3085_cross_file_spurious" {
  fn fdecl(name : String, line : Int32, body : @ast.Stmt?) -> @ast.FuncDecl {
    {
      ..Default::default(),
      loc: @source.SourceLoc::new(line, 1),
      return_type: @ast.Type::int(),
      name,
      params: [],
      body,
      source_file: "",
    }
  }
  let loc_call = @source.SourceLoc::new(1, 25)
  let call = @ast.Expr::CallPtr(
    @ast.Expr::Identifier("add", loc_call, @ast.Type::void_type()),
    [
      @ast.Expr::Literal(1, loc_call, @ast.Type::int()),
      @ast.Expr::Literal(2, loc_call, @ast.Type::int()),
    ],
    loc_call,
    @ast.Type::void_type(),
  )
  // main_b.c（拼接序行 1）调用 add；lib_a2.c（拼接序行 9 起）定义 add
  let main_b = fdecl("main", 1, Some(@ast.Stmt::Return(Some(call), loc_call)))
  let lib_a2 = fdecl(
    "add",
    9,
    Some(
      @ast.Stmt::Return(
        Some(@ast.Expr::Literal(0, loc_call, @ast.Type::int())),
        loc_call,
      ),
    ),
  )
  let tc = TypeChecker::new()
  tc.set_file_boundaries([(1, 1, "main_b.c"), (2, 10, "lib_a2.c")])
  let (_, _, warns, _) = tc.check({
    structs: [],
    unions: [],
    globals: [],
    funcs: [main_b, lib_a2],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_false(
    warns.exists(w => w.code == 3085),
    msg="跨文件调用不得报 W3085（文案行号指向另一文件——修前实得 \{warns.map(w => w.code.to_string()).join(",")}）",
  )
  // 反向锚：同文件前向（调用行 1 < 定义行 9，同边界内）仍须报——门只
  // 挡跨文件，不放松同文件判据（既有锚 issue214_w3085 亦锁此面，本处
  // 双形态对照防门写反）
  let main_same = fdecl(
    "main",
    1,
    Some(
      @ast.Stmt::Return(
        Some(
          @ast.Expr::CallPtr(
            @ast.Expr::Identifier("add2", loc_call, @ast.Type::void_type()),
            [],
            loc_call,
            @ast.Type::void_type(),
          ),
        ),
        loc_call,
      ),
    ),
  )
  let add_same = fdecl(
    "add2",
    9,
    Some(
      @ast.Stmt::Return(
        Some(@ast.Expr::Literal(0, loc_call, @ast.Type::int())),
        loc_call,
      ),
    ),
  )
  let tc2 = TypeChecker::new()
  tc2.set_file_boundaries([(1, 10, "t.c")])
  let (_, _, warns2, _) = tc2.check({
    structs: [],
    unions: [],
    globals: [],
    funcs: [main_same, add_same],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_true(
    warns2.exists(w => w.code == 3085),
    msg="同文件前向调用仍须报 W3085（实得 \{warns2.map(w => w.code.to_string()).join(",")}）",
  )
}

///|
/// 红锚 M05-b1i（P2，A-1+A-2 连坐）：`const int a[3]; typeof(a[0]) x;
/// x = 5;`——clang c2x error（赋值只读）。修前双缺陷叠加误收：A-1
/// `subscript_type` 一维分支丢数组 const 位（对照多维分支显式传导），
/// A-2 `resolve_typeof_in_type` 的 `t.set_const(is_const)` **覆写**清掉
/// 传导的 const——单修任一处均不足（M05 报告实验副本预演：A-1+A-2
/// 叠加才转 E3049 红，970/970 绿）。
test "m05_red_typeof_const_subscript_loses_const" {
  let loc = @source.SourceLoc::new(3, 3)
  // const int a[3] —— array_of 构造器无 const 参，set_const 补数组位
  let a_decl : @ast.Stmt = @ast.Stmt::VarDecl(
    @ast.Type::array_of(@ast.Type::int(), [3]).set_const(true),
    "a",
    Some(
      @ast.Expr::InitList(
        [
          {
            designators: [],
            value: @ast.Expr::Literal(1, loc, @ast.Type::int()),
          },
          {
            designators: [],
            value: @ast.Expr::Literal(2, loc, @ast.Type::int()),
          },
          {
            designators: [],
            value: @ast.Expr::Literal(3, loc, @ast.Type::int()),
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
  // typeof(a[0]) x; —— Typeof(Index(a,0), is_const=false, unqual=false)
  let x_decl : @ast.Stmt = @ast.Stmt::VarDecl(
    @ast.Type::Typeof(
      @ast.Expr::Index(
        @ast.Expr::Identifier("a", loc, @ast.Type::void_type()),
        @ast.Expr::Literal(0, loc, @ast.Type::int()),
        loc,
        @ast.Type::void_type(),
      ),
      false,
      false,
    ),
    "x",
    None,
    [],
    false,
    false,
    loc,
  )
  // x = 5;
  let assign : @ast.Stmt = @ast.Stmt::Expr(
    @ast.Expr::Assign(
      @ast.AssignOp::Assign,
      @ast.Expr::Identifier("x", loc, @ast.Type::void_type()),
      @ast.Expr::Literal(5, loc, @ast.Type::int()),
      loc,
      @ast.Type::void_type(),
    ),
    loc,
  )
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc,
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(@ast.Stmt::Block([a_decl, x_decl, assign], loc)),
    source_file: "t.c",
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check({
    structs: [],
    unions: [],
    globals: [],
    funcs: [main],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_true(
    errs.exists(e => e.code == 3049),
    msg="typeof(const 数组元素) 继承 const，赋值应报 E3049（实得 \{errs.map(e => e.code.to_string()).join(",")}）",
  )
}

///|
/// 红锚 M05-b1h（P2，A-3）：`char c = 1; typeof(c) x = 300;`——
/// sizeof(x) 应为 1（typeof 结果 = char；clang c2x 实测）。修前
/// `process_var_decl` 的 Some(init) 分支用**初始化器类型**（300=int）
/// 推导（auto 式），x 定型 int（sizeof 4，js+native 双臂实锤）。
test "m05_red_typeof_with_init_uses_operand_not_init" {
  let loc = @source.SourceLoc::new(2, 3)
  let c_decl : @ast.Stmt = @ast.Stmt::VarDecl(
    @ast.Type::char(),
    "c",
    Some(@ast.Expr::Literal(1, loc, @ast.Type::int())),
    [],
    false,
    false,
    loc,
  )
  let x_decl : @ast.Stmt = @ast.Stmt::VarDecl(
    @ast.Type::Typeof(
      @ast.Expr::Identifier("c", loc, @ast.Type::void_type()),
      false,
      false,
    ),
    "x",
    Some(@ast.Expr::Literal(300, loc, @ast.Type::int())),
    [],
    false,
    false,
    loc,
  )
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc,
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(@ast.Stmt::Block([c_decl, x_decl], loc)),
    source_file: "t.c",
  }
  let tc = TypeChecker::new()
  let (typed, errs, _, _) = tc.check({
    structs: [],
    unions: [],
    globals: [],
    funcs: [main],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_eq(errs.length(), 0, msg="本锚只锁定型面，不要求诊断")
  guard typed.funcs[0].body is Some(@ast.Stmt::Block(stmts, _)) else {
    fail("main body 缺失")
  }
  guard stmts[1] is @ast.Stmt::VarDecl(x_ty, "x", _, _, _, _, _) else {
    fail("stmts[1] 应为 x 的 VarDecl")
  }
  assert_true(
    x_ty.kind() is TK_Char,
    msg="typeof(c) x = 300 的 x 应定型 char（sizeof 1，操作数类型），不得用 init 的 int（实得 kind=\{x_ty.name()}）",
  )
}

///|
/// 红锚 M05-b2d（P2，A-4）：`union A{int x;}; struct A{int y;};`——
/// C11 §6.2.3 struct/union/enum 共享 tag 命名空间，clang error
/// "use of 'A' with tag type that does not match previous declaration"；
/// 修前 vitro COMPILE-OK 误收（Struct(name)/Union(name) 同名并存，
/// types 层无域不变量——M05 报告 A-4）。修后两轮注册完成后交叉查
/// 报 E3092_TagKindMismatch。
test "m05_red_union_struct_same_tag_accepted" {
  let loc = @source.SourceLoc::new(1, 1)
  let u_decl : @ast.StructDecl = {
    loc,
    name: "A",
    fields: [{ ty: @ast.Type::int(), name: "x", }],
    is_forward: false,
  }
  let s_decl : @ast.StructDecl = {
    loc,
    name: "A",
    fields: [{ ty: @ast.Type::int(), name: "y", }],
    is_forward: false,
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check({
    structs: [s_decl],
    unions: [u_decl],
    globals: [],
    funcs: [],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_true(
    errs.exists(e => e.code == 3092),
    msg="union A 与 struct A 同名 tag 应报 E3092（C11 §6.2.3 共享 tag 命名空间；实得 \{errs.map(e => e.code.to_string()).join(",")}）",
  )
}

///|
/// 红锚 M05-b2c（P2，A-4+A-5 连坐）：`union A{int x;}; struct A{union A u;
/// int y;};`——修前 value_member_cycle 的 Struct|Union 共臂裸 name 判环
///（struct A 的成员 union A u 先撞 structs 表的 A 自身）报 **E3072 循环
/// 包含** + FIX 建议改指针——但用户改指针后仍编译不过（真因是 tag 冲突
/// 被误报吞掉，clang 报 tag mismatch）。修后：E3092 在场 且 E3072 不再
/// 误报（环检测键带 tag 种类前缀——s:A/u:A 不互撞）。
test "m05_red_tag_conflict_no_bogus_e3072" {
  let loc = @source.SourceLoc::new(1, 1)
  let u_decl : @ast.StructDecl = {
    loc,
    name: "A",
    fields: [{ ty: @ast.Type::int(), name: "x", }],
    is_forward: false,
  }
  let s_decl : @ast.StructDecl = {
    loc,
    name: "A",
    fields: [
      { ty: @ast.Type::union_type("A"), name: "u", },
      { ty: @ast.Type::int(), name: "y", },
    ],
    is_forward: false,
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check({
    structs: [s_decl],
    unions: [u_decl],
    globals: [],
    funcs: [],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_true(
    errs.exists(e => e.code == 3092),
    msg="tag 冲突应报 E3092（实得 \{errs.map(e => e.code.to_string()).join(",")}）",
  )
  assert_false(
    errs.exists(e => e.code == 3072),
    msg="tag 冲突形态不得误报 E3072 循环包含（真因 tag 种类不同——键带前缀后不互撞；实得 \{errs.map(e => e.code.to_string()).join(",")}）",
  )
}

///|
/// 锚 M05-反向（防误伤）：①不同名 struct/union 并存零诊断；②struct 值
/// 自引用（**真环**）仍报 E3072——键前缀化后同种类照撞，环检测不放松。
test "m05_anchor_tag_check_no_false_positive" {
  let loc = @source.SourceLoc::new(1, 1)
  // ① 不同名：struct B{int b;}; union C{int c;}; —— 零诊断
  let s_b : @ast.StructDecl = {
    loc,
    name: "B",
    fields: [{ ty: @ast.Type::int(), name: "b", }],
    is_forward: false,
  }
  let u_c : @ast.StructDecl = {
    loc,
    name: "C",
    fields: [{ ty: @ast.Type::int(), name: "c", }],
    is_forward: false,
  }
  let tc = TypeChecker::new()
  let (_, errs1, _, _) = tc.check({
    structs: [s_b],
    unions: [u_c],
    globals: [],
    funcs: [],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_eq(
    errs1.length(),
    0,
    msg="不同名 struct/union 并存零诊断（实得 \{errs1.map(e => e.code.to_string()).join(",")}）",
  )
  // ② 真环：struct N{ struct N next; int v; } —— E3072 保持
  let s_n : @ast.StructDecl = {
    loc,
    name: "N",
    fields: [
      { ty: @ast.Type::struct_type("N"), name: "next", },
      { ty: @ast.Type::int(), name: "v", },
    ],
    is_forward: false,
  }
  let tc2 = TypeChecker::new()
  let (_, errs2, _, _) = tc2.check({
    structs: [s_n],
    unions: [],
    globals: [],
    funcs: [],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_true(
    errs2.exists(e => e.code == 3072),
    msg="struct 值自引用真环必须仍报 E3072（实得 \{errs2.map(e => e.code.to_string()).join(",")}）",
  )
}

///|
/// 红锚 M09-C2（P3）：参数重定义 `void f(int x){ int x = 200; }` 的
/// E3001 报位置 **0:0**——修前 visit_func_decl 的 declare_var 不传
/// loc~（默认 SourceLoc(0,0)），clang 给 1:21 精确位置。修后报参数
/// 声明点（line>0）。
test "m09_red_param_redef_loc_zero_zero" {
  let loc = @source.SourceLoc::new(1, 21)
  let f_decl : @ast.FuncDecl = {
    ..Default::default(),
    loc: @source.SourceLoc::new(1, 1),
    return_type: @ast.Type::void_type(),
    name: "f",
    params: [{ ..Default::default(), ty: @ast.Type::int(), name: "x", loc, }],
    body: Some(
      @ast.Stmt::Block(
        [
          @ast.Stmt::VarDecl(
            @ast.Type::int(),
            "x",
            Some(@ast.Expr::Literal(200, loc, @ast.Type::int())),
            [],
            false,
            false,
            loc,
          ),
        ],
        loc,
      ),
    ),
    source_file: "t.c",
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check({
    structs: [],
    unions: [],
    globals: [],
    funcs: [f_decl],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  let redef = errs.filter(e => e.code == 3001)
  assert_true(
    redef.length() > 0,
    msg="参数重定义应报 E3001（实得 \{errs.map(e => e.code.to_string()).join(",")}）",
  )
  assert_true(
    redef[0].line > 0,
    msg="E3001 位置不得是 0:0（修前 declare_var 缺 loc~ 落默认 SourceLoc(0,0)；实得 \{redef[0].line}:\{redef[0].column}）",
  )
}

///|
/// 红锚 M09-C1（P3）：Label 重定义借 E3001_VarRedeclared——文案对但码
/// 是变量重定义码（fix_suggestion 面向变量场景张冠李戴）。修后走独立
/// 码 E3093_LabelRedeclared。
test "m09_red_label_redef_borrows_e3001" {
  let loc = @source.SourceLoc::new(2, 1)
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc,
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(
      @ast.Stmt::Block(
        [
          @ast.Stmt::Label("lab", @ast.Stmt::Block([], loc), loc),
          @ast.Stmt::Label("lab", @ast.Stmt::Block([], loc), loc),
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
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check({
    structs: [],
    unions: [],
    globals: [],
    funcs: [main],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_true(
    errs.exists(e => e.code == 3093),
    msg="Label 重定义应走独立码 E3093（修前借 E3001；实得 \{errs.map(e => e.code.to_string()).join(",")}）",
  )
  assert_false(
    errs.exists(e => e.code == 3001),
    msg="Label 重定义不得再报变量重定义码 E3001",
  )
}

///|
/// 红锚 M09-C4（P3）：`int x = x;` 自引用零提示——predeclared 机制
///（#75 合法面）使其静默通过；clang -Wuninitialized 对自身初始化中
/// 值读取给警。修后裸 Identifier 自引用报 W3094；反向：引用**外部**
/// 同名变量（`int x = y;`）零提示不误伤。
test "m09_red_self_init_reference_silent" {
  let loc = @source.SourceLoc::new(2, 3)
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
            @ast.Type::int(),
            "x",
            Some(@ast.Expr::Identifier("x", loc, @ast.Type::void_type())),
            [],
            false,
            false,
            loc,
          ),
        ],
        loc,
      ),
    ),
    source_file: "t.c",
  }
  let tc = TypeChecker::new()
  let (_, _, warns, _) = tc.check({
    structs: [],
    unions: [],
    globals: [],
    funcs: [main],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_true(
    warns.exists(w => w.code == 3094),
    msg="int x = x; 自引用值读取应报 W3094（实得 \{warns.map(w => w.code.to_string()).join(",")}）",
  )
  // 反向：int x = y;（y 外部变量）不报
  let main2 : @ast.FuncDecl = {
    ..main,
    body: Some(
      @ast.Stmt::Block(
        [
          @ast.Stmt::VarDecl(
            @ast.Type::int(),
            "x",
            Some(@ast.Expr::Identifier("y", loc, @ast.Type::int())),
            [],
            false,
            false,
            loc,
          ),
        ],
        loc,
      ),
    ),
  }
  let tc2 = TypeChecker::new()
  let g_y : @ast.GlobalDecl = {
    ..Default::default(),
    loc,
    ty: @ast.Type::int(),
    name: "y",
    init: Some(@ast.Expr::Literal(1, loc, @ast.Type::int())),
    source_file: "t.c",
  }
  let (_, _, warns2, _) = tc2.check({
    structs: [],
    unions: [],
    globals: [g_y],
    funcs: [main2],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_false(
    warns2.exists(w => w.code == 3094),
    msg="引用外部变量不得报 W3094（实得 \{warns2.map(w => w.code.to_string()).join(",")}）",
  )
}

///|
/// 红锚 M09-A8（P3）：数组 designator 索引值域/常量性 typeck 不查
///（`int a[3]={[9]=1};` / `{[n]=2}` clang 双 error；修前 typeck 零、
/// codegen 兜底报 E0 归类「内部错误」无教学 fix）。修后：越界报
/// E3095、非常量报 E3096；反向：合法 `[1]=2` 零诊断。
test "m09_red_designator_index_unchecked" {
  fn desig_arr(
    desig : @ast.Expr,
    val : Int32,
    loc : @source.SourceLoc,
  ) -> @ast.Stmt {
    @ast.Stmt::VarDecl(
      @ast.Type::array_of(@ast.Type::int(), [3]),
      "a",
      Some(
        @ast.Expr::InitList(
          [
            {
              designators: [@ast.Designator::Index(desig)],
              value: @ast.Expr::Literal(val, loc, @ast.Type::int()),
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
  }
  let loc = @source.SourceLoc::new(2, 3)
  // [9] = 1 —— 越界
  let main_oob : @ast.FuncDecl = {
    ..Default::default(),
    loc,
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(
      @ast.Stmt::Block(
        [desig_arr(@ast.Expr::Literal(9, loc, @ast.Type::int()), 1, loc)],
        loc,
      ),
    ),
    source_file: "t.c",
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check({
    structs: [],
    unions: [],
    globals: [],
    funcs: [main_oob],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_true(
    errs.exists(e => e.code == 3095),
    msg="[9] 越界应报 E3095（实得 \{errs.map(e => e.code.to_string()).join(",")}）",
  )
  // [n] = 2 —— 非常量（n 局部变量）
  let main_var : @ast.FuncDecl = {
    ..Default::default(),
    loc,
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(
      @ast.Stmt::Block(
        [
          @ast.Stmt::VarDecl(
            @ast.Type::int(),
            "n",
            Some(@ast.Expr::Literal(1, loc, @ast.Type::int())),
            [],
            false,
            false,
            loc,
          ),
          desig_arr(@ast.Expr::Identifier("n", loc, @ast.Type::int()), 2, loc),
        ],
        loc,
      ),
    ),
    source_file: "t.c",
  }
  let tc2 = TypeChecker::new()
  let (_, errs2, _, _) = tc2.check({
    structs: [],
    unions: [],
    globals: [],
    funcs: [main_var],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_true(
    errs2.exists(e => e.code == 3096),
    msg="[n] 非常量应报 E3096（实得 \{errs2.map(e => e.code.to_string()).join(",")}）",
  )
  // 反向：[1] = 2 合法零诊断
  let main_ok : @ast.FuncDecl = {
    ..Default::default(),
    loc,
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(
      @ast.Stmt::Block(
        [desig_arr(@ast.Expr::Literal(1, loc, @ast.Type::int()), 2, loc)],
        loc,
      ),
    ),
    source_file: "t.c",
  }
  let tc3 = TypeChecker::new()
  let (_, errs3, _, _) = tc3.check({
    structs: [],
    unions: [],
    globals: [],
    funcs: [main_ok],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_eq(
    errs3.length(),
    0,
    msg="[1]=2 合法零诊断（实得 \{errs3.map(e => e.code.to_string()).join(",")}）",
  )
}

///|
/// 红锚 M09-C6（P3）：`char s[3]="abc"` 恰满形态 W3008 判据文案——
/// 3 字节进 char[3] 不是「超长」，是 NUL 没地方放（gcc15/clang21/22
/// 新警告族 -Wunterminated-string-initialization 的判据；本机 clang 22
/// 默认档恰满零警、真超长 -Wexcess-initializers）。修后文案区分两态：
/// 恰满 =「'\0' 被截断」；真超长 =「超过数组大小」照旧。
test "m09_red_w3008_exact_fit_wording" {
  fn char_arr(
    size : Int32,
    lit : String,
    name : String,
    loc : @source.SourceLoc,
  ) -> @ast.Stmt {
    @ast.Stmt::VarDecl(
      @ast.Type::array_of(@ast.Type::char(), [size]),
      name,
      Some(@ast.Expr::StringLiteral(lit, loc, @ast.Type::void_type())),
      [],
      false,
      false,
      loc,
    )
  }
  let loc = @source.SourceLoc::new(2, 3)
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc,
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(
      @ast.Stmt::Block(
        [
          char_arr(3, "abc", "s", loc),
          char_arr(2, "abc", "t", loc),
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
  let tc = TypeChecker::new()
  let (_, _, warns, _) = tc.check({
    structs: [],
    unions: [],
    globals: [],
    funcs: [main],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  let w3008 = warns.filter(w => w.code == 3008)
  assert_eq(
    w3008.length(),
    2,
    msg="恰满与真超长各一条 W3008（实得 \{warns.map(w => w.code.to_string()).join(",")}）",
  )
  assert_true(
    w3008.exists(w => w.message.contains("截断")),
    msg="恰满形态文案应区分「'\\0' 被截断」（实得第一条：\{w3008[0].message}）",
  )
  assert_true(
    w3008.exists(w => w.message.contains("超过数组大小")),
    msg="真超长文案照旧「超过数组大小」",
  )
}

///|
/// 红锚 P2-2（PR #504 审阅处置，2026-11-13）：同名 tag 冲突**源序单报**——
/// clang 口径 error 只落后声明侧；修前两循环各报一条（双报）且先侧消息
/// 方向倒置（1:8「已用作 union」指向的恰是先写的 struct）。
test "p22_tag_conflict_source_order_single_report" {
  let s_loc = @source.SourceLoc::new(1, 1)
  let u_loc = @source.SourceLoc::new(2, 1)
  let s_decl : @ast.StructDecl = {
    loc: s_loc,
    name: "A",
    fields: [{ ty: @ast.Type::int(), name: "x", }],
    is_forward: false,
  }
  let u_decl : @ast.StructDecl = {
    loc: u_loc,
    name: "A",
    fields: [{ ty: @ast.Type::int(), name: "y", }],
    is_forward: false,
  }
  let tc = TypeChecker::new()
  let (_, errs, _, _) = tc.check({
    structs: [s_decl],
    unions: [u_decl],
    globals: [],
    funcs: [],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  let e3092 = errs.filter(e => e.code == 3092)
  assert_eq(
    e3092.length(),
    1,
    msg="E3092 须源序单报（只落后声明侧；实得 \{e3092.length()} 条：\{errs.map(e => e.code.to_string() + "@" + e.line.to_string()).join(",")}）",
  )
  assert_eq(
    e3092[0].line,
    2,
    msg="报错位置须落后声明（union 侧 line 2；实得 line \{e3092[0].line}——方向倒置是 P2-2 缺陷形态）",
  )
  assert_true(
    e3092[0].message.contains("已用作 struct"),
    msg="后侧 union 撞先侧 struct——消息方向须「已用作 struct」",
  )
}

///|
/// 红锚 P3-1（PR #504 审阅处置，2026-11-13）：null pointer constant 判据
/// 全形态——qsort compar 位传 1-1 / (int)0（整型常量表达式==0，C11
/// §6.7.9）应与字面量 0 同零诊断；修前只认裸字面量 0，此两形态假阳
/// E3029（clang 仅 -Wnon-literal-null-conversion 提示级）。
test "p31_null_const_expr_1_minus_1_and_cast_zero_pass" {
  let loc = @source.SourceLoc::new(3, 3)
  let mk = fn(compar : @ast.Expr) -> Array[TypeError] {
    let arr_decl : @ast.Stmt = @ast.Stmt::VarDecl(
      @ast.Type::array_of(@ast.Type::int(), [2]),
      "arr",
      None,
      [],
      false,
      false,
      loc,
    )
    let qsort_call : @ast.Stmt = @ast.Stmt::Expr(
      @ast.Expr::CallPtr(
        @ast.Expr::Identifier("qsort", loc, @ast.Type::void_type()),
        [
          @ast.Expr::Identifier("arr", loc, @ast.Type::void_type()),
          @ast.Expr::Literal(2, loc, @ast.Type::int()),
          @ast.Expr::Literal(4, loc, @ast.Type::int()),
          compar,
        ],
        loc,
        @ast.Type::void_type(),
      ),
      loc,
    )
    let main : @ast.FuncDecl = {
      ..Default::default(),
      loc,
      return_type: @ast.Type::int(),
      name: "main",
      params: [],
      body: Some(@ast.Stmt::Block([arr_decl, qsort_call], loc)),
      source_file: "t.c",
    }
    let tc = TypeChecker::new()
    let (_, errs, _, _) = tc.check({
      structs: [],
      unions: [],
      globals: [],
      funcs: [main],
      classes: [],
      templates: [],
      template_instantiations: [],
    })
    errs
  }
  // ① 1-1：整型常量表达式==0——零诊断（修前 E3029 假阳）
  let e1 = mk(
    @ast.Expr::Binary(
      Sub,
      @ast.Expr::Literal(1, loc, @ast.Type::int()),
      @ast.Expr::Literal(1, loc, @ast.Type::int()),
      loc,
      @ast.Type::int(),
    ),
  )
  let e1c = e1.map(e => e.code.to_string()).join(",")
  assert_eq(
    e1.filter(e => e.code == 3029).length(),
    0,
    msg="qsort compar 位 1-1（常量表达式==0）应零诊断（C11 §6.7.9；实得 \{e1c}",
  )
  // ② (int)0：cast 形态同零诊断
  let e2 = mk(
    @ast.Expr::Cast(
      @ast.Expr::Literal(0, loc, @ast.Type::int()),
      @ast.Type::int(),
      loc,
      @ast.Type::int(),
    ),
  )
  let e2c = e2.map(e => e.code.to_string()).join(",")
  assert_eq(
    e2.filter(e => e.code == 3029).length(),
    0,
    msg="qsort compar 位 (int)0 应零诊断（实得 \{e2c}",
  )
}
