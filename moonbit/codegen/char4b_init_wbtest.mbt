///|
/// #424（审阅 v2 B1 批，2026-11-02）——全局初始化装载层宽度族白盒锚。
///
/// 缺陷族（M11-A1 / M13-A-3 / M13-C-6）：全局/static 的 char 目标初始化
/// （数组 designated / 标量字面量 / char[] 字符串逐字节）一律经
/// globals_init_32 的 4 字节 store 落盘——负值符号扩展成 0xFFFFFFFF 越权
/// 抹掉相邻三字节，相邻全局**无初始化记录时无法覆盖回来**（永久污染，
/// 探针 `char a[4]={[1]=-1}` 读 `0 -1 -1 -1`、`char a=300; char b;` 读
/// b=1）。修复：`push_char_init_byte` 单源——char 字节 init 按 4 字节对齐
/// 字小端合并（字节级位运算，不越权），组装时按字基址升序**前插**到
/// globals_init_32 头部；非 char 条目照旧精确写自身 4/8 字节范围。
///
/// 装载序不变量（本文件第 5 锚锁定）：char 合并字在前，32/64 位条目在
/// 后——共享同一个 4 字节字的非 char 邻居（紧排布局）由后续条目覆盖
/// 收敛；无初始化的邻居字节本就该是静态零。运行期内存真值由 corpus
/// 七例（char_global_desig_byte_write 等）经 clang_direct 直拍锁定，
/// 本文件锚 codegen 输出表形态。

///|
/// 探针 1 形态（M11-A1 pa）：`char a[4] = {[1] = -1}; char b[2] = {0,0};`
/// ——旧形态 a[1] 推 4 字节记录 (1025, -1) 越权写 1025..1027（读回 -1×3）；
/// 新形态 a 与 b 的 6 个字节合并成两个字：(1024, 0x0000FF00) 与
/// (1028, 0)。
test "char4b: global char designated init merges into one word (#424 F1)" {
  let gen = BytecodeGen::new()
  let (output, errors) = gen.generate(
    mini_program(
      [
        {
          ..Default::default(),
          loc: loc(1),
          ty: @ast.Type::array_of(@ast.Type::char(), [4]),
          name: "a",
          init: Some(
            @ast.Expr::InitList(
              [
                {
                  designators: [
                    @ast.Designator::Index(
                      @ast.Expr::Literal(1, loc(1), @ast.Type::int()),
                    ),
                  ],
                  value: @ast.Expr::Literal(-1, loc(1), @ast.Type::int()),
                },
              ],
              loc(1),
              @ast.Type::void_type(),
            ),
          ),
        },
        {
          ..Default::default(),
          loc: loc(2),
          ty: @ast.Type::array_of(@ast.Type::char(), [2]),
          name: "b",
          init: Some(
            @ast.Expr::InitList(
              [
                {
                  designators: [],
                  value: @ast.Expr::Literal(0, loc(2), @ast.Type::int()),
                },
                {
                  designators: [],
                  value: @ast.Expr::Literal(0, loc(2), @ast.Type::int()),
                },
              ],
              loc(2),
              @ast.Type::void_type(),
            ),
          ),
        },
      ],
      [],
    ),
  )
  assert_eq(errors.length(), 0, msg="char designated 不应报错")
  let o = output.unwrap()
  assert_eq(
    o.globals_init_32,
    [(1024U, 65280), (1028U, 0)],
    msg="char designated 须按 4 字节对齐字小端合并（a[1]=-1 → 0x0000FF00=65280），禁逐字节 4 字节直写",
  )
}

///|
/// 探针 3 形态（M13-A-3 p03）：`char a = 300; char b; char c = 66;`
/// ——旧形态 (1024, 300) 4 字节写把 0x01 泄漏进无初始化的 b（读 1）；
/// 新形态三字节合并成 (1024, 0x0042002C=4325420)：a=44、b=静态零、c=66。
test "char4b: global char scalar literal init packs neighbours (#424 F2)" {
  let gen = BytecodeGen::new()
  let (output, errors) = gen.generate(
    mini_program(
      [
        {
          ..Default::default(),
          loc: loc(1),
          ty: @ast.Type::char(),
          name: "a",
          init: Some(@ast.Expr::Literal(300, loc(1), @ast.Type::int())),
        },
        { ..Default::default(), loc: loc(2), ty: @ast.Type::char(), name: "b", },
        {
          ..Default::default(),
          loc: loc(3),
          ty: @ast.Type::char(),
          name: "c",
          init: Some(@ast.Expr::Literal(66, loc(3), @ast.Type::int())),
        },
      ],
      [],
    ),
  )
  assert_eq(errors.length(), 0)
  let o = output.unwrap()
  assert_eq(
    o.globals_init_32,
    [(1024U, 4325420)],
    msg="char 标量三邻居须合并一个字（44 | 66<<16），未初始化的 b 保持静态零",
  )
}

///|
/// M13-C-6 连坐：`char s[6] = "Hello";` ——旧形态 6 条逐字节 4 字节记录
/// （表+装载双重膨胀）；新形态两字 (1024, 'H'|'e'<<8|'l'<<16|'l'<<24)
/// 与 (1028, 'o')。
test "char4b: global char[] string init merges bytes per word (#424 F3 / M13-C-6)" {
  let gen = BytecodeGen::new()
  let (output, errors) = gen.generate(
    mini_program(
      [
        {
          ..Default::default(),
          loc: loc(1),
          ty: @ast.Type::array_of(@ast.Type::char(), [6]),
          name: "s",
          init: Some(
            @ast.Expr::StringLiteral(
              "Hello",
              loc(1),
              @ast.Type::pointer_to(@ast.Type::char()),
            ),
          ),
        },
      ],
      [],
    ),
  )
  assert_eq(errors.length(), 0)
  let o = output.unwrap()
  assert_eq(
    o.globals_init_32,
    [(1024U, 1819043144), (1028U, 111)],
    msg="字符串直写须按字合并：'H'|'e'<<8|'l'<<16|'l'<<24=1819043144、'o'=111",
  )
}

///|
/// struct 字段臂（flatten_global_init 递归路径）：`struct Q {char b; char c;
/// int a;}; struct Q q = {-1};` ——紧排 b@1024/c@1025/a@1026..1029，旧形态
/// (1024, -1) 4 字节写抹掉 c 与 a 的低两字节（读 -1 / 65535）；新形态
/// (1024, 0xFF) 只写 b，c/a 保持静态零。
test "char4b: struct char member via init list is byte-width (#424 struct arm)" {
  let gen = BytecodeGen::new()
  let sdecl : @ast.StructDecl = {
    ..Default::default(),
    loc: loc(1),
    name: "Q",
    fields: [
      { ty: @ast.Type::char(), name: "b", },
      { ty: @ast.Type::char(), name: "c", },
      { ty: @ast.Type::int(), name: "a", },
    ],
  }
  let q : @ast.GlobalDecl = {
    ..Default::default(),
    loc: loc(2),
    ty: @ast.Type::struct_type("Q"),
    name: "q",
    init: Some(
      @ast.Expr::InitList(
        [
          {
            designators: [],
            value: @ast.Expr::Literal(-1, loc(2), @ast.Type::int()),
          },
        ],
        loc(2),
        @ast.Type::void_type(),
      ),
    ),
  }
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc: loc(3),
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(
      @ast.Stmt::Block(
        [
          @ast.Stmt::Return(
            Some(@ast.Expr::Literal(0, loc(3), @ast.Type::int())),
            loc(3),
          ),
        ],
        loc(3),
      ),
    ),
    source_file: "t.c",
  }
  let (output, errors) = gen.generate({
    structs: [sdecl],
    unions: [],
    globals: [q],
    funcs: [main],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_eq(errors.length(), 0)
  let o = output.unwrap()
  assert_eq(
    o.globals_init_32,
    [(1024U, 255)],
    msg="struct char 首字段只写 1 字节（0xFF=255），c/a 不被符号扩展抹零",
  )
}

///|
/// 装载序不变量：`int i = 2; char c = 1;`（i 先声明占 1024..1027，c 紧排
/// 1028）——char 合并字 (1028, 1) 必须**前插**在非 char 条目 (1024, 2)
/// 之前：装载时先写字内邻居字节 0，再由 i 的精确 4 字节写覆盖收敛。
/// 若实现把 char 字后置，紧排共享字的邻居（如 `char c4=5; int i4=0x11223344`
/// ——矩阵语料 L4）低 3 字节会被清零。
test "char4b: merged char words are loaded before non-char records (#424 invariant)" {
  let gen = BytecodeGen::new()
  let (output, errors) = gen.generate(
    mini_program(
      [
        {
          ..Default::default(),
          loc: loc(1),
          ty: @ast.Type::int(),
          name: "i",
          init: Some(@ast.Expr::Literal(2, loc(1), @ast.Type::int())),
        },
        {
          ..Default::default(),
          loc: loc(2),
          ty: @ast.Type::char(),
          name: "c",
          init: Some(@ast.Expr::Literal(1, loc(2), @ast.Type::int())),
        },
      ],
      [],
    ),
  )
  assert_eq(errors.length(), 0)
  let o = output.unwrap()
  assert_eq(
    o.globals_init_32,
    [(1028U, 1), (1024U, 2)],
    msg="char 合并字须前插（装载序在 32 位条目之前）——后置会清掉共享字邻居",
  )
}

///|
/// #424 F4（M11-A2 pc）：static 局部指针以**裸数组名**初始化——旧形态
/// emit_static_init 的 Identifier 臂只查 func_index，`None => ()` 静默
/// 置 0 → 运行期 E3083（全局路径 #264 有 push_global_addr_init 兜底，
/// static 路径漏连坐）。新形态：与全局路径同源回填
/// GLOBAL_START + 数组偏移。
test "static4: static local ptr init from array name resolves address (#424 F4 / M11-A2)" {
  let gen = BytecodeGen::new()
  let arr : @ast.GlobalDecl = {
    ..Default::default(),
    loc: loc(1),
    ty: @ast.Type::array_of(@ast.Type::int(), [3]),
    name: "arr",
    init: Some(
      @ast.Expr::InitList(
        [
          {
            designators: [],
            value: @ast.Expr::Literal(5, loc(1), @ast.Type::int()),
          },
          {
            designators: [],
            value: @ast.Expr::Literal(6, loc(1), @ast.Type::int()),
          },
          {
            designators: [],
            value: @ast.Expr::Literal(7, loc(1), @ast.Type::int()),
          },
        ],
        loc(1),
        @ast.Type::void_type(),
      ),
    ),
  }
  // int main(void) { static int *p = arr; return 0; }
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc: loc(2),
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(
      @ast.Stmt::Block(
        [
          @ast.Stmt::VarDecl(
            @ast.Type::pointer_to(@ast.Type::int()),
            "p",
            Some(
              @ast.Expr::Identifier(
                "arr",
                loc(2),
                @ast.Type::array_of(@ast.Type::int(), [3]),
              ),
            ),
            [],
            true,
            false,
            loc(2),
          ),
          @ast.Stmt::Return(
            Some(@ast.Expr::Literal(0, loc(2), @ast.Type::int())),
            loc(2),
          ),
        ],
        loc(2),
      ),
    ),
    source_file: "t.c",
  }
  let (output, errors) = gen.generate({
    structs: [],
    unions: [],
    globals: [arr],
    funcs: [main],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_eq(errors.length(), 0, msg="static 指针裸名初始化不应报错")
  let o = output.unwrap()
  // arr@1024（12 字节）、static p 4 对齐 bump 到 1036；地址 = 0x1000+1024
  assert_true(
    o.globals_init_32.exists(e => e.0 == 1036U && e.1 == 5120),
    msg="static 指针槽 1036 须回填数组名地址 0x1000+1024=5120（旧形态静默 NULL）",
  )
}

///|
/// #424 F5（M11-A3 pd）：static 局部函数指针数组——旧形态
/// emit_static_scalar_array_init 的 4 字节臂 `_ => push((addr, 0))` 把
/// 函数名元素静默落 0 → CallPtr「索引 0 越界」TRAP（全局路径 #201-B
/// 修过、static 漏连坐）。新形态：与全局路径同源解析 func_index。
test "static4: static local fn-ptr array init resolves func index (#424 F5 / M11-A3)" {
  let af_ty = @ast.Type::pointer_to(@ast.Type::function(@ast.Type::int(), []))
  let mk_fn = (n : String, v : Int32) => {
    let f : @ast.FuncDecl = {
      ..Default::default(),
      loc: loc(2),
      return_type: @ast.Type::int(),
      name: n,
      params: [],
      body: Some(
        @ast.Stmt::Block(
          [
            @ast.Stmt::Return(
              Some(@ast.Expr::Literal(v, loc(2), @ast.Type::int())),
              loc(2),
            ),
          ],
          loc(2),
        ),
      ),
      source_file: "t.c",
    }
    f
  }
  // int main(void) { static int (*fns[2])(void) = {f1, f2}; return 0; }
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc: loc(3),
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(
      @ast.Stmt::Block(
        [
          @ast.Stmt::VarDecl(
            @ast.Type::array_of(af_ty, [2]),
            "fns",
            Some(
              @ast.Expr::InitList(
                [
                  {
                    designators: [],
                    value: @ast.Expr::Identifier("f1", loc(3), af_ty),
                  },
                  {
                    designators: [],
                    value: @ast.Expr::Identifier("f2", loc(3), af_ty),
                  },
                ],
                loc(3),
                @ast.Type::void_type(),
              ),
            ),
            [],
            true,
            false,
            loc(3),
          ),
          @ast.Stmt::Return(
            Some(@ast.Expr::Literal(0, loc(3), @ast.Type::int())),
            loc(3),
          ),
        ],
        loc(3),
      ),
    ),
    source_file: "t.c",
  }
  let gen = BytecodeGen::new()
  let (output, errors) = gen.generate({
    structs: [],
    unions: [],
    globals: [],
    funcs: [mk_fn("f1", 11), mk_fn("f2", 22), main],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_eq(errors.length(), 0)
  let o = output.unwrap()
  let slots = o.globals_init_32.filter(e => e.0 >= 1024U && e.0 < 1024U + 8U)
  assert_eq(
    slots.length(),
    2,
    msg="fns 两槽各须恰有一条初始化写记录",
  )
  for s in slots {
    assert_true(
      s.1 != 0,
      msg="static 函数指针元素不得落 0（M11-A3：CallPtr 索引 0 越界 TRAP）",
    )
  }
  assert_true(
    slots[0].1 != slots[1].1,
    msg="f1/f2 须解析为不同函数索引",
  )
}

///|
/// #424 F6（M12-A4 p07）：嵌套 struct 赋值的 dst 地址槽——旧形态
/// gen_struct_copy 用固定 temp_slot1 存 dst 地址且在求值右侧**之前**存入，
/// 内层 `b = c`（call 实参位置）复用同槽覆写 → 外层拷贝写错目标
/// （`a = id(b = c)` 输出 1 2 7）。T-P0-6 的按深度分槽机制
/// （get_assign_addr_slot）已存在但 gen_struct_copy 未接入。新形态：dst
/// 槽按 assign_nest_depth 分层，两层嵌套分配两个不同槽。
test "struct-assign: nested struct copy takes per-depth dst slot (#424 F6 / M12-A4)" {
  let sdecl : @ast.StructDecl = {
    ..Default::default(),
    loc: loc(1),
    name: "S",
    fields: [
      { ty: @ast.Type::int(), name: "x", },
      { ty: @ast.Type::int(), name: "y", },
    ],
  }
  let sty = @ast.Type::struct_type("S")
  let id_fn : @ast.FuncDecl = {
    ..Default::default(),
    loc: loc(2),
    return_type: sty,
    name: "id",
    params: [{ ty: sty, name: "v", loc: loc(2), default: None, }],
    body: Some(
      @ast.Stmt::Block(
        [
          @ast.Stmt::Return(
            Some(@ast.Expr::Identifier("v", loc(2), sty)),
            loc(2),
          ),
        ],
        loc(2),
      ),
    ),
    source_file: "t.c",
  }
  let mk_decl = (n : String) => {
    let d : @ast.Stmt = @ast.Stmt::VarDecl(
      sty,
      n,
      None,
      [],
      false,
      false,
      loc(4),
    )
    d
  }
  // a = id(b = c);
  let nested : @ast.Stmt = @ast.Stmt::Expr(
    @ast.Expr::Assign(
      @ast.AssignOp::Assign,
      @ast.Expr::Identifier("a", loc(5), sty),
      @ast.Expr::CallPtr(
        @ast.Expr::Identifier("id", loc(5), sty),
        [
          @ast.Expr::Assign(
            @ast.AssignOp::Assign,
            @ast.Expr::Identifier("b", loc(5), sty),
            @ast.Expr::Identifier("c", loc(5), sty),
            loc(5),
            sty,
          ),
        ],
        loc(5),
        sty,
      ),
      loc(5),
      sty,
    ),
    loc(5),
  )
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc: loc(4),
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(
      @ast.Stmt::Block(
        [
          mk_decl("a"),
          mk_decl("b"),
          mk_decl("c"),
          nested,
          @ast.Stmt::Return(
            Some(@ast.Expr::Literal(0, loc(6), @ast.Type::int())),
            loc(6),
          ),
        ],
        loc(4),
      ),
    ),
    source_file: "t.c",
  }
  let gen = BytecodeGen::new()
  let (output, errors) = gen.generate({
    structs: [sdecl],
    unions: [],
    globals: [],
    funcs: [id_fn, main],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_eq(errors.length(), 0, msg="嵌套 struct 赋值不应报错")
  let _ = output.unwrap()
  // 外层 depth1 / 内层 depth2 各拿一个独立 dst 槽——旧形态固定
  // temp_slot1 时此数组恒空（gen_struct_copy 不调 get_assign_addr_slot）
  assert_eq(
    gen.assign_addr_slots.length(),
    2,
    msg="两层嵌套 struct 赋值须分配两个不同 dst 地址槽（M12-A4：固定槽被内层覆写）",
  )
}

///|
/// 最小程序壳：globals + 返回 0 的 main（本文件锚共用）。
fn mini_program(
  globals : Array[@ast.GlobalDecl],
  extra_funcs : Array[@ast.FuncDecl],
) -> @ast.ProgramNode {
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc: loc(9),
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(
      @ast.Stmt::Block(
        [
          @ast.Stmt::Return(
            Some(@ast.Expr::Literal(0, loc(9), @ast.Type::int())),
            loc(9),
          ),
        ],
        loc(9),
      ),
    ),
    source_file: "t.c",
  }
  {
    structs: [],
    unions: [],
    globals,
    funcs: [main, ..extra_funcs],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
}
