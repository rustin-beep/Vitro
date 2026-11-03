///|
/// T5-d init 面白盒锚：数组尺寸推断（一维/字符串字面量两轨）/ 超量
/// W3005 / W3008（#50 批②降级，原 E3005/E3008）/ struct 初始化（位置 + designated + 嵌套）/ 多维
/// 扁平标量填充。

///|
/// 全局数组 `int a[] = {1,2,3}`：dims[0] 与 array_size 推断为 3；超量
/// 元素报 W3005（推断后按 3 判；#50 批②降级）。
test "init_array_size_inference" {
  let loc = @source.SourceLoc::new(1, 1)
  fn elem(v : Int32, loc : @source.SourceLoc) -> @ast.InitElement {
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
  let (_, _, warns2, _) = tc2.check(prog2)
  assert_eq(warns2.length(), 1)
  assert_true(warns2[0].code == 3005)
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
  let (_, _, warns2, _) = tc2.check(prog2)
  assert_eq(warns2.length(), 1)
  assert_true(warns2[0].code == 3008)
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
    is_forward: false,
  }
  fn init_list(
    elems : Array[@ast.InitElement],
    loc : @source.SourceLoc,
  ) -> @ast.Expr {
    @ast.Expr::InitList(elems, loc, @ast.Type::void_type())
  }
  fn lit(v : Int32, loc : @source.SourceLoc) -> @ast.Expr {
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
  // 混合 → 零诊断（P2-3 审阅批 2026-10-23：C11 6.7.9p20 混合合法——
  // designator 后裸项续位；旧 E3005 误报与 clang 双实测推翻，锚改锁零 error）
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
  assert_eq(
    errs3.length(),
    0,
    msg="混合 designated+位置合法（P2-3）零 error",
  )
}

///|
/// 多维扁平标量填充：`int m[2][3] = {1,2,3,4,5,6}` 合法（行主序）；
/// 嵌套超维 E3005。
test "init_multidim_flat_scalar" {
  let loc = @source.SourceLoc::new(1, 1)
  fn lit(v : Int32, loc : @source.SourceLoc) -> @ast.Expr {
    @ast.Expr::Literal(v, loc, @ast.Type::int())
  }
  fn flat(elems : Array[Int32], loc : @source.SourceLoc) -> @ast.Expr {
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
  let (_, _, warns2, _) = tc2.check({ ..prog, globals: [m2], })
  assert_eq(warns2.length(), 1)
  assert_true(warns2[0].code == 3005)
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

///|
/// #196B（2026-10-21，C11 §6.7.9p11 括号包裹 + p14 字符串初始化）：
/// `char s[2] = {"abc"}` ≡ 裸字符串 `char s[2] = "abc"`——单元素花括号
/// 字符串走 StringLiteral 同款路径（长度校验/W3008），不再按元素循环
/// 把 "abc" 定型 char[4] 误报 E3006。红锚：修复前 errs 含 3006。
test "char_array_braced_string_init_issue196b" {
  let loc = @source.SourceLoc::new(1, 1)
  fn ok_case(arr : @ast.Type, lit : String) -> @ast.ProgramNode {
    let g : @ast.GlobalDecl = {
      ..Default::default(),
      loc,
      ty: arr,
      name: "s",
      init: Some(
        @ast.Expr::InitList(
          [
            {
              designators: [],
              value: @ast.Expr::StringLiteral(
                lit,
                loc,
                @ast.Type::array_of(@ast.Type::char(), [3]),
              ),
            },
          ],
          loc,
          @ast.Type::void_type(),
        ),
      ),
      source_file: "t.c",
    }
    {
      structs: [],
      unions: [],
      globals: [g],
      funcs: [],
      classes: [],
      templates: [],
      template_instantiations: [],
    }
  }
  // char s[2] = {"abc"}：恰含 \0 超长 1——W3008 警告非错误（clang 同款
  // warning: initializer-string too long），errors 必须 0
  let tc = TypeChecker::new()
  let (_, errs, warns, _) = tc.check(
    ok_case(@ast.Type::array_of(@ast.Type::char(), [2]), "abc"),
  )
  assert_eq(
    errs.length(),
    0,
    msg="花括号字符串不得报 E3006：\{errs.length()}",
  )
  // 超长警告面：与裸字符串同款 W3008
  assert_true(
    warns.length() == 1 && warns[0].code == 3008,
    msg="超长应走 W3008（实得 \{warns.length()} 条）",
  )
  // char s[4] = {"abc"}：恰好放下（含 \0）——零错误零警告
  let tc2 = TypeChecker::new()
  let (_, errs2, warns2, _) = tc2.check(
    ok_case(@ast.Type::array_of(@ast.Type::char(), [4]), "abc"),
  )
  assert_eq(errs2.length(), 0)
  assert_eq(warns2.length(), 0)
  // int a[2] = {"x"}：非 char 基类型不进新路径——仍按元素循环语义
  //（字符串对 int 元素的既有拒绝面不变，走 E3006）
  let g3 : @ast.GlobalDecl = {
    ..Default::default(),
    loc,
    ty: @ast.Type::array_of(@ast.Type::int(), [2]),
    name: "a",
    init: Some(
      @ast.Expr::InitList(
        [
          {
            designators: [],
            value: @ast.Expr::StringLiteral(
              "x",
              loc,
              @ast.Type::array_of(@ast.Type::char(), [2]),
            ),
          },
        ],
        loc,
        @ast.Type::void_type(),
      ),
    ),
    source_file: "t.c",
  }
  let tc3 = TypeChecker::new()
  let (_, errs3, _, _) = tc3.check({
    structs: [],
    unions: [],
    globals: [g3],
    funcs: [],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_true(errs3.length() > 0, msg="int 数组收字符串仍须拒绝")
}

///|
/// ds 审阅批 2026-10-31（PR #401 P2）：init.mbt 定型回写路径行为锚——
/// `char g[] = {"\xff"}` 推导形态（空 dims ⇒ array_size 0）走
/// check_array_init StringLiteral 臂的回写分支。**B6 批（#429）翻面**：
/// 字面量承载治本（解码层拆源字符字节 + 码元=字节口径）后 `\xff` 产
/// 单码元 U+00FF ⇒ 计 1 字节 ⇒ 回写尺寸 **2**（FF + NUL）——与三方
/// 编译器（Win clang 22.1.4 / WSL gcc 15.2 / WSL clang 21.1.8）对齐，
/// 原 KNOWN_DIVERGENCE（UTF-8 U+00FF 计 2 ⇒ 3）销案。红条件：回退
/// UTF-8 计长口径 ⇒ 回写 3 ⇒ 本锚红（与 expr_wbtest
/// `string_literal_byte_len` 分别锁 init 回写/expr 定型两条路径）。
test "char_arr_deduce_size_writeback_utf8_ds" {
  let loc = @source.SourceLoc::new(1, 1)
  let g : @ast.GlobalDecl = {
    ..Default::default(),
    loc,
    ty: @ast.Type::array_of(@ast.Type::char(), []), // char g[]——空 dims 推导
    name: "g",
    init: Some(
      @ast.Expr::InitList(
        [
          {
            designators: [],
            value: @ast.Expr::StringLiteral(
              "\u00ff",
              loc,
              @ast.Type::void_type(),
            ),
          },
        ],
        loc,
        @ast.Type::void_type(),
      ),
    ),
    source_file: "t.c",
  }
  let tc = TypeChecker::new()
  let (prog, errs, _, _) = tc.check({
    structs: [],
    unions: [],
    globals: [g],
    funcs: [],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_eq(errs.length(), 0, msg="推导形态不得报错")
  match prog.globals[0].ty {
    Array(_, size, dims, _, _, _) => {
      assert_eq(
        size,
        2,
        msg="char g[] 回写尺寸须为字节 1（\\xff 单码元）+ NUL（UTF-8 口径给 3 即红）",
      )
      assert_eq(
        dims.length(),
        0,
        msg="dims 不动（Rust 同形——仅回写 array_size）",
      )
    }
    _ => fail("char g[] 定型后应为 char 数组")
  }
}

///|
/// ds 审阅批 2026-10-31（PR #401 P2）：init.mbt 多维子数组 W3008 路径
/// 行为锚——`char w[1][2] = {"\xff"}`：外层 InitList 单元素经
/// check_array_elem_value 进 char[N] 子数组臂。**B6 批（#429）翻面**：
/// 字面量承载治本后 `\xff` 计 1 字节（1+1 ≤ 2 恰满合法）⇒ **零警**——
/// 与三方编译器（Win clang 22.1.4 / WSL gcc 15.2 / WSL clang 21.1.8，
/// M09 P9a 实测）对齐，原 KNOWN_DIVERGENCE（UTF-8 计 2 ⇒ 2+1>2 假警）
/// 销案。红条件：回退 UTF-8 计长口径 ⇒ W3008 假警复活 ⇒ 本锚红。
/// 真实超长形态（`"ab"` 进 char[1][2]：2+1>2）仍须 W3008——见下方
/// 反向锚，防翻面过宽。
test "char_arr2d_substring_w3008_utf8_ds" {
  let loc = @source.SourceLoc::new(1, 1)
  let w : @ast.GlobalDecl = {
    ..Default::default(),
    loc,
    ty: @ast.Type::array_of(@ast.Type::char(), [1, 2]), // char w[1][2]
    name: "w",
    init: Some(
      @ast.Expr::InitList(
        [
          {
            designators: [],
            value: @ast.Expr::StringLiteral(
              "\u00ff",
              loc,
              @ast.Type::void_type(),
            ),
          },
        ],
        loc,
        @ast.Type::void_type(),
      ),
    ),
    source_file: "t.c",
  }
  let tc = TypeChecker::new()
  let (_, errs, warns, _) = tc.check({
    structs: [],
    unions: [],
    globals: [w],
    funcs: [],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_eq(
    errs.length(),
    0,
    msg="恰满形态合法不报错（C11 §6.7.9p14）",
  )
  assert_eq(
    warns.length(),
    0,
    msg="恰满 1+1 ≤ 2 零警（UTF-8 口径回退即 W3008 假警复活，红）",
  )
}

///|
/// B6 批（#429）A10 翻面的反向锚：真实超长形态（`"ab"` 两字节 + NUL = 3
/// > 2）仍须 W3008——防翻面过宽把「字节口径计长」误收成「恒零警」。
test "char_arr2d_substring_overlong_still_w3008_b6" {
  let loc = @source.SourceLoc::new(1, 1)
  let w : @ast.GlobalDecl = {
    ..Default::default(),
    loc,
    ty: @ast.Type::array_of(@ast.Type::char(), [1, 2]), // char w[1][2]
    name: "w",
    init: Some(
      @ast.Expr::InitList(
        [
          {
            designators: [],
            value: @ast.Expr::StringLiteral("ab", loc, @ast.Type::void_type()),
          },
        ],
        loc,
        @ast.Type::void_type(),
      ),
    ),
    source_file: "t.c",
  }
  let tc = TypeChecker::new()
  let (_, errs, warns, _) = tc.check({
    structs: [],
    unions: [],
    globals: [w],
    funcs: [],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_eq(errs.length(), 0, msg="超长警告形态不报错")
  assert_true(
    warns.length() == 1 && warns[0].code == 3008,
    msg="2 字节 + NUL > 2 须 W3008（恒零警即翻面过宽，红）",
  )
}

///|
/// #424 B1 遗留批审阅 P2-2（2026-11-04）：struct char 成员豁免路径
/// （check_field_value 的 s_suppress 包裹）行为锚——此前该路径零单测锚
///（突变关掉 s_suppress 后 132 条 typeck 单测全绿、仅差分 digest 红）。
/// 域内形态：首成员 -1（Neg）/ 'x'（字符常量）零 W3053；负锚：域外
/// 成员 300 教学警恰一条（防恒真，同 a=200 口径）。
test "w3053_struct_field_char_domain(#424 B1 followup P2-2)" {
  let loc = @source.SourceLoc::new(1, 1)
  let qt : @ast.StructDecl = {
    loc,
    name: "Q",
    fields: [
      { ty: @ast.Type::char(), name: "b", },
      { ty: @ast.Type::char(), name: "c", },
      { ty: @ast.Type::int(), name: "a", },
    ],
    is_forward: false,
  }
  fn init_list(
    elems : Array[@ast.InitElement],
    loc : @source.SourceLoc,
  ) -> @ast.Expr {
    @ast.Expr::InitList(elems, loc, @ast.Type::void_type())
  }
  fn int_lit(v : Int32, loc : @source.SourceLoc) -> @ast.Expr {
    @ast.Expr::Literal(v, loc, @ast.Type::int())
  }
  fn char_lit(v : Int32, loc : @source.SourceLoc) -> @ast.Expr {
    @ast.Expr::Literal(v, loc, @ast.Type::char())
  }
  fn neg_lit(v : Int32, loc : @source.SourceLoc) -> @ast.Expr {
    @ast.Expr::Unary(@ast.UnaryOp::Neg, int_lit(v, loc), loc, @ast.Type::int())
  }
  fn qdecl(name : String, init : @ast.Expr) -> @ast.GlobalDecl {
    {
      ..Default::default(),
      loc,
      ty: @ast.Type::struct_type("Q"),
      name,
      init: Some(init),
      source_file: "t.c",
    }
  }
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc: @source.SourceLoc::new(90, 1),
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(
      @ast.Stmt::Return(
        Some(int_lit(0, @source.SourceLoc::new(90, 1))),
        @source.SourceLoc::new(90, 1),
      ),
    ),
    source_file: "t.c",
  }
  // 域内：{-1, 'x', 5} → 零 W3053
  let tc1 = TypeChecker::new()
  let (_, _, warns1, _) = tc1.check({
    structs: [qt],
    unions: [],
    globals: [
      qdecl(
        "g_ok",
        init_list(
          [
            { designators: [], value: neg_lit(1, loc), },
            { designators: [], value: char_lit(120, loc), },
            { designators: [], value: int_lit(5, loc), },
          ],
          loc,
        ),
      ),
    ],
    funcs: [main],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_false(
    warns1.exists(w => w.code == 3053),
    msg="struct char 成员域内初始化 {-1,'x',5} 不得误报 W3053（s_suppress 豁免面）",
  )
  // 负锚：域外 {300, 'x', 5} → 教学警恰一条
  let tc2 = TypeChecker::new()
  let (_, _, warns2, _) = tc2.check({
    structs: [qt],
    unions: [],
    globals: [
      qdecl(
        "g_bad",
        init_list(
          [
            { designators: [], value: int_lit(300, loc), },
            { designators: [], value: char_lit(120, loc), },
            { designators: [], value: int_lit(5, loc), },
          ],
          loc,
        ),
      ),
    ],
    funcs: [main],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_eq(
    warns2.filter(w => w.code == 3053).length(),
    1,
    msg="struct char 成员域外 300 须保留教学警 W3053（真截断面，防恒真）",
  )
}
