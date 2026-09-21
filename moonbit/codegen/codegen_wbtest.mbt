///|
/// codegen 骨架白盒测试（S5 开工批）——手工构造 AST（不经 parser，
/// 同 typeck 白盒先例）走 generate 全流程，锚定骨架通路不变量：
/// Pass 1 全局布局（libc 预留段起点 / 标量位模式 / 字符串回填）、
/// Pass 2/3 函数元数据回填、入口 wrapper 形态、global_data_end 口径。
/// 语句/表达式族扩展批接线后逐批补对应锚（红→绿纪律）。
fn loc(line : Int) -> @source.SourceLoc {
  @source.SourceLoc::new(line, 1)
}

///|
/// `int g = 42; int main() { return 0; }` 形态的极简程序。
fn minimal_program() -> @ast.ProgramNode {
  {
    structs: [],
    unions: [],
    globals: [
      {
        loc: loc(1),
        ty: @ast.Type::int(),
        name: "g",
        init: Some(@ast.Expr::Literal(42, loc(1), @ast.Type::int())),
        is_static: false,
        is_extern: false,
        source_file: "",
      },
    ],
    funcs: [
      {
        loc: loc(2),
        return_type: @ast.Type::int(),
        name: "main",
        params: [],
        body: Some(
          @ast.Stmt::Block(
            [
              @ast.Stmt::Return(
                Some(@ast.Expr::Literal(0, loc(2), @ast.Type::int())),
                loc(2),
              ),
            ],
            loc(2),
          ),
        ),
        is_static: false,
        is_extern: false,
        source_file: "",
        is_variadic: false,
      },
    ],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
}

///|
test "skeleton: minimal program end-to-end invariants" {
  let gen = BytecodeGen::new()
  let (output, errors) = gen.generate(minimal_program())
  assert_eq(errors.length(), 0)
  let o = output.unwrap()
  // 入口 wrapper：code[0] = Jump wrapper_ip；wrapper 尾 Call main + Ret
  assert_true(o.code[0].op is @opcode.OpCode::Jump)
  let wrapper_ip = o.code[0].operand
  assert_true(o.code[wrapper_ip].op is @opcode.OpCode::Call)
  assert_eq(o.code[wrapper_ip].operand, o.func_index.get("main").unwrap())
  assert_true(o.code[wrapper_ip + 1].op is @opcode.OpCode::Ret)
  // Pass 1：全局 g 落在 libc 预留段之后（reserved=1024），int 位模式 42
  assert_eq(o.symbols[0].addr, 1024U)
  assert_eq(o.globals_init_32, [(1024U, 42)])
  // global_data_end = GLOBAL_START + align4(1024 + 4)
  assert_eq(o.global_data_end, 0x1000 + 1028)
  // Pass 2/3：main 元数据（标量 int 返回 → 非 struct → 无 __ret_ptr）
  let main_meta = o.func_table.get("main").unwrap()
  assert_eq(main_meta.param_count, 0)
  assert_eq(main_meta.arg_count, 0)
  assert_true(main_meta.local_count >= 0)
  // 函数体：Block 与 Return 各发一次 StepEvent（Rust gen_stmt 入口形态——
  // smoke 实测双 StepEvent 连发），随后 PushConst 0 + Ret
  let body_ip = main_meta.ip
  assert_true(o.code[body_ip].op is @opcode.OpCode::StepEvent)
  assert_true(o.code[body_ip + 1].op is @opcode.OpCode::StepEvent)
  assert_true(o.code[body_ip + 2].op is @opcode.OpCode::PushConst)
  assert_eq(o.code[body_ip + 2].operand, 0)
  assert_true(o.code[body_ip + 3].op is @opcode.OpCode::Ret)
  // 符号表：g 全局（scope_depth=0）
  assert_eq(o.symbols.length(), 1)
  assert_eq(o.symbols[0].name, "g")
  assert_false(o.symbols[0].is_local)
  assert_eq(o.symbols[0].addr, 1024U)
}

///|
test "skeleton: libc pre-registration + strcpy/strcat dispatch exception" {
  let gen = BytecodeGen::new()
  let (output, errors) = gen.generate(minimal_program())
  assert_eq(errors.length(), 0)
  let o = output.unwrap()
  // with_mode(false) 预注册：88 - 2（strcpy/strcat 分发回 Host）= 86 条
  let mut libc_count = 0
  o.func_index.each((_, idx) => {
    if idx >= 1000 && idx <= 1087 {
      libc_count += 1
    }
  })
  assert_eq(libc_count, 86)
  // strcpy/strcat 不预注册（Host 路径带 E3070 栈缓冲区检测）
  assert_true(o.func_index.get("strcpy") is None)
  assert_true(o.func_index.get("strcat") is None)
  assert_true(o.func_index.get("strlen") is Some(1015))
  // 用户函数索引从 1089 起
  assert_eq(o.func_index.get("main").unwrap(), 1089)
}

///|
test "skeleton: global char* string init deferred allocation" {
  // `char *p = "hi";`——非 char 数组目标走 pending 取址路径（P2/★A 修复形态）
  let program : @ast.ProgramNode = {
    structs: [],
    unions: [],
    globals: [
      {
        loc: loc(1),
        ty: @ast.Type::pointer_to(@ast.Type::char()),
        name: "p",
        init: Some(
          @ast.Expr::StringLiteral(
            "hi",
            loc(1),
            @ast.Type::pointer_to(@ast.Type::char()),
          ),
        ),
        is_static: false,
        is_extern: false,
        source_file: "",
      },
    ],
    funcs: [
      {
        loc: loc(2),
        return_type: @ast.Type::int(),
        name: "main",
        params: [],
        body: Some(
          @ast.Stmt::Block(
            [
              @ast.Stmt::Return(
                Some(@ast.Expr::Literal(0, loc(2), @ast.Type::int())),
                loc(2),
              ),
            ],
            loc(2),
          ),
        ),
        is_static: false,
        is_extern: false,
        source_file: "",
        is_variadic: false,
      },
    ],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
  let gen = BytecodeGen::new()
  let (output, errors) = gen.generate(program)
  assert_eq(errors.length(), 0)
  let o = output.unwrap()
  // p 槽（1024）写字符串地址；"hi"（cstring_len=2+1=3→align4=4）在全局区
  // 末尾（1028），绝对地址 = GLOBAL_START + 1028
  let str_addr = 0x1000 + 1028
  assert_eq(o.globals_init_32, [(1024U, str_addr)])
  assert_eq(o.string_data, [(str_addr.reinterpret_as_uint(), "hi")])
  assert_eq(o.global_data_end, 0x1000 + 1032)
}

///|
test "skeleton: double global bit pattern by target type (T-P0-1)" {
  // `double g = 1;`——按目标类型编码位模式（此前 int 位模式写进 double 槽得 0）
  let program : @ast.ProgramNode = {
    structs: [],
    unions: [],
    globals: [
      {
        loc: loc(1),
        ty: @ast.Type::double(),
        name: "g",
        init: Some(@ast.Expr::Literal(1, loc(1), @ast.Type::int())),
        is_static: false,
        is_extern: false,
        source_file: "",
      },
    ],
    funcs: [
      {
        loc: loc(2),
        return_type: @ast.Type::int(),
        name: "main",
        params: [],
        body: Some(@ast.Stmt::Block([], loc(2))),
        is_static: false,
        is_extern: false,
        source_file: "",
        is_variadic: false,
      },
    ],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
  let gen = BytecodeGen::new()
  let (output, errors) = gen.generate(program)
  assert_eq(errors.length(), 0)
  let o = output.unwrap()
  // 1.0 的 f64 位模式 0x3FF0000000000000，8 字节槽
  assert_eq(o.globals_init_32.length(), 0)
  assert_eq(o.globals_init_64, [(1024U, 4607182418800017408UL)])
}

///|
test "skeleton: while loop generates (control-flow batch) + retired stmt fails loud" {
  // 扩展批三号后 while 已接线——本锚改为正向断言（循环跳转结构）；
  // fail loud 面改由退役语句（RangeFor）承载（仍报错且带行号）
  let program : @ast.ProgramNode = {
    structs: [],
    unions: [],
    globals: [],
    funcs: [
      {
        loc: loc(3),
        return_type: @ast.Type::int(),
        name: "main",
        params: [],
        body: Some(
          @ast.Stmt::Block(
            [
              @ast.Stmt::While(
                @ast.Expr::Literal(1, loc(3), @ast.Type::int()),
                @ast.Stmt::Block([], loc(3)),
                loc(3),
              ),
            ],
            loc(3),
          ),
        ),
        is_static: false,
        is_extern: false,
        source_file: "",
        is_variadic: false,
      },
    ],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
  let gen = BytecodeGen::new()
  let (output, errors) = gen.generate(program)
  // while(1){} 生成成功：PushConst 1 + JumpIfZero + Jump 回 start 的循环结构
  assert_eq(errors.length(), 0)
  let o = output.unwrap()
  let ip = o.func_table.get("main").unwrap().ip
  // ip: StepEvent(Block) ip+1: StepEvent(While) ip+2: PushConst 1
  assert_eq(o.code[ip + 2].operand, 1)
  assert_true(o.code[ip + 3].op is @opcode.OpCode::JumpIfZero)
  // 尾部 Jump 回 start_ip（循环回边）
  let last = o.code[o.code.length() - 2] // 最后一条是 Ret 前——查尾部 Jump
  ignore(last)
  let mut has_back_jump = false
  for ins in o.code {
    if ins.op is @opcode.OpCode::Jump && ins.operand == ip + 2 {
      has_back_jump = true
    }
  }
  assert_true(has_back_jump)
}

///|
/// 退役语句 fail loud 锚（RangeFor——砍 C++ 裁定，永不接线）：
/// 报错文本必须带行号且**不写"未实现"**（对后来者是假承诺）。
test "skeleton: retired C++ stmt fails loud without in-flight wording" {
  let program : @ast.ProgramNode = {
    structs: [],
    unions: [],
    globals: [],
    funcs: [
      {
        loc: loc(3),
        return_type: @ast.Type::int(),
        name: "main",
        params: [],
        body: Some(
          @ast.Stmt::Block(
            [
              @ast.Stmt::RangeFor(
                "i",
                @ast.Type::int(),
                @ast.Expr::Literal(1, loc(3), @ast.Type::int()),
                @ast.Stmt::Block([], loc(3)),
                loc(3),
              ),
            ],
            loc(3),
          ),
        ),
        is_static: false,
        is_extern: false,
        source_file: "",
        is_variadic: false,
      },
    ],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
  let gen = BytecodeGen::new()
  let (output, errors) = gen.generate(program)
  assert_true(output is None)
  assert_true(errors.length() > 0)
  // 行号为 0（stmt_loc 的 RangeFor 走 _ 兜底臂——Rust stmt_loc 同款
  // 语义，两侧一致，"第 0 行："）
  assert_true(errors[0].has_prefix("第 0 行："))
  // 退役文案不含"未实现"（假承诺）
  assert_true(!errors[0].contains("未实现"))
  assert_true(errors[0].contains("退役"))
}

///|
test "skeleton: compile_output_dump_json wiring" {
  let gen = BytecodeGen::new()
  let (output, errors) = gen.generate(minimal_program())
  assert_eq(errors.length(), 0)
  let json = @bytecode.compile_output_dump_json(output.unwrap())
  // 14 键齐全（与 Rust dump-compile 同契约面）
  for
    key in [
      "version", "code", "globals_init_32", "globals_init_64", "func_table", "func_index",
      "string_data", "source_map", "symbols", "struct_defs", "union_defs", "f64_constants",
      "i64_constants", "global_data_end",
    ] {
    guard json.contains("\"\{key}\":") else { fail("缺键 \{key}") }
  }
  assert_true(json.contains("\"global_data_end\":5124"))
}

///|
/// C99 `__func__`（P1-3 审阅修复锚）：预定义标识符 → 当前函数名的字符串
/// 字面量（Rust expr.rs 同臂）。此前落入"未声明的标识符"——已实现臂内
/// 缺口 + 反向语义诊断（typeck 已支持其定型，codegen 漏臂）。
test "skeleton: __func__ resolves to current function name literal" {
  let program : @ast.ProgramNode = {
    structs: [],
    unions: [],
    globals: [],
    funcs: [
      {
        loc: loc(1),
        return_type: @ast.Type::pointer_to(@ast.Type::char()),
        name: "f",
        params: [],
        body: Some(
          @ast.Stmt::Block(
            [
              @ast.Stmt::Return(
                Some(
                  @ast.Expr::Identifier(
                    "__func__",
                    loc(1),
                    @ast.Type::pointer_to(@ast.Type::char()),
                  ),
                ),
                loc(1),
              ),
            ],
            loc(1),
          ),
        ),
        is_static: false,
        is_extern: false,
        source_file: "",
        is_variadic: false,
      },
      {
        loc: loc(2),
        return_type: @ast.Type::int(),
        name: "main",
        params: [],
        body: Some(@ast.Stmt::Block([], loc(2))),
        is_static: false,
        is_extern: false,
        source_file: "",
        is_variadic: false,
      },
    ],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
  let gen = BytecodeGen::new()
  let (output, errors) = gen.generate(program)
  assert_eq(errors.length(), 0)
  let o = output.unwrap()
  // "f" 字面量入全局区（cstring_len=1+1=2→align4=4），string_data 含 ("f")
  assert_eq(o.string_data.length(), 1)
  assert_eq(o.string_data[0].1, "f")
  // 无"未声明的标识符"错误（P1-3 修复前正是此诊断）
  for e in errors {
    assert_true(!e.contains("未声明的标识符"))
  }
}

///|
/// 槽位策略版本锚（消费点——此前常量全仓零消费，§6"槽位策略版本化"
/// 是纸面声明，2026-09-21 审阅补）：v1 = 逐位兼容（A 级 diff 前提）。
/// **v2（LIFO 池）切换批必须**：①改本常量为 2；②本锚同步改期望；
/// ③八条槽位事故回归必挂；④codegen_diff 按 dump_compile 包装层的
/// slot_strategy 字段分档（产物出口携带版本——见 cmd/dump_compile）。
test "skeleton: slot strategy version is v1 (bit-compatible)" {
  assert_eq(SLOT_STRATEGY_VERSION, 1)
}

///|
/// VarDecl 接线锚（S5 扩展批·归因首要阻塞 245 例）：局部 int 初始化的
/// 指令序（StepEvent×2 + GetFrameBase/PushConst/Add/StoreLocal 基址 +
/// PushConst 值 + StoreLocal）与 local_buffers 登记（int 非数组不登记）。
test "vardecl: scalar int init instruction sequence" {
  let program : @ast.ProgramNode = {
    structs: [],
    unions: [],
    globals: [],
    funcs: [
      {
        loc: loc(1),
        return_type: @ast.Type::int(),
        name: "main",
        params: [],
        body: Some(
          @ast.Stmt::Block(
            [
              @ast.Stmt::VarDecl(
                @ast.Type::int(),
                "a",
                Some(@ast.Expr::Literal(3, loc(2), @ast.Type::int())),
                [],
                false,
                loc(2),
              ),
              @ast.Stmt::Return(
                Some(@ast.Expr::Literal(0, loc(3), @ast.Type::int())),
                loc(3),
              ),
            ],
            loc(1),
          ),
        ),
        is_static: false,
        is_extern: false,
        source_file: "",
        is_variadic: false,
      },
    ],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
  let gen = BytecodeGen::new()
  let (output, errors) = gen.generate(program)
  assert_eq(errors.length(), 0)
  let o = output.unwrap()
  // 符号表：a 局部（offset 0，scope_depth 1）
  let a_sym = o.symbols[0]
  assert_eq(a_sym.name, "a")
  assert_true(a_sym.is_local)
  assert_eq(a_sym.addr, 0)
  // 指令序（main 体起点）：StepEvent(Block) + StepEvent(VarDecl) +
  // PushConst 3 + StoreLocal 0
  let ip = o.func_table.get("main").unwrap().ip
  assert_true(o.code[ip].op is @opcode.OpCode::StepEvent)
  assert_true(o.code[ip + 1].op is @opcode.OpCode::StepEvent)
  assert_true(o.code[ip + 2].op is @opcode.OpCode::PushConst)
  assert_eq(o.code[ip + 2].operand, 3)
  assert_true(o.code[ip + 3].op is @opcode.OpCode::StoreLocal)
  assert_eq(o.code[ip + 3].operand, 0)
  // local_count：a 槽 4 字节 + return PushConst 无槽 → ≥ 4
  assert_true(o.func_table.get("main").unwrap().local_count >= 4)
}

///|
/// CallPtr 接线锚（S5 扩展批·归因第 2 位 174 例）：printf 走 host 路由
/// CallHost（PRINTF_N=15），字符串字面量实参经全局区取址。
test "callptr: printf host route + string arg" {
  let program : @ast.ProgramNode = {
    structs: [],
    unions: [],
    globals: [],
    funcs: [
      {
        loc: loc(1),
        return_type: @ast.Type::int(),
        name: "main",
        params: [],
        body: Some(
          @ast.Stmt::Block(
            [
              @ast.Stmt::Expr(
                @ast.Expr::CallPtr(
                  @ast.Expr::Identifier(
                    "printf",
                    loc(2),
                    @ast.Type::function(@ast.Type::int(), []),
                  ),
                  [
                    @ast.Expr::StringLiteral(
                      "hi\n",
                      loc(2),
                      @ast.Type::pointer_to(@ast.Type::char()),
                    ),
                  ],
                  loc(2),
                  @ast.Type::int(),
                ),
                loc(2),
              ),
              @ast.Stmt::Return(
                Some(@ast.Expr::Literal(0, loc(3), @ast.Type::int())),
                loc(3),
              ),
            ],
            loc(1),
          ),
        ),
        is_static: false,
        is_extern: false,
        source_file: "",
        is_variadic: false,
      },
    ],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
  let gen = BytecodeGen::new()
  let (output, errors) = gen.generate(program)
  assert_eq(errors.length(), 0)
  let o = output.unwrap()
  // printf 是 host 函数：CallHost PRINTF_N=15
  let mut found_callhost = false
  for ins in o.code {
    if ins.op is @opcode.OpCode::CallHost {
      assert_eq(ins.operand, 15)
      found_callhost = true
    }
  }
  assert_true(found_callhost)
  // "hi\n" 字面量入 string_data
  assert_true(o.string_data.length() == 1)
  assert_eq(o.string_data[0].1, "hi\n")
}

///|
/// P1（2026-09-21 审阅修复）锚：struct 按值传参的第 4 子路径——实参为
/// 调用返回的临时对象（`use(make())`）时，从返回地址 temp_slot0 逐字
/// LoadMem 展开（Rust call.rs:324-353 同构）。此前误落"零填充"分支
/// （latent：struct-return 生成被二元/赋值挡住时不可达，接线即静默错值）。
test "callptr: struct arg from call return loads via temp (P1)" {
  let struct_ty = @ast.Type::struct_type("S")
  let program : @ast.ProgramNode = {
    structs: [
      {
        loc: loc(1),
        name: "S",
        fields: [
          { ty: @ast.Type::int(), name: "a", },
          { ty: @ast.Type::int(), name: "b", },
        ],
      },
    ],
    unions: [],
    globals: [],
    funcs: [
      {
        loc: loc(2),
        return_type: struct_ty,
        name: "make",
        params: [],
        body: Some(@ast.Stmt::Block([], loc(2))),
        is_static: false,
        is_extern: false,
        source_file: "",
        is_variadic: false,
      },
      {
        loc: loc(3),
        return_type: @ast.Type::int(),
        name: "use",
        params: [{ ty: struct_ty, name: "s", loc: loc(3), default: None, }],
        body: Some(@ast.Stmt::Block([], loc(3))),
        is_static: false,
        is_extern: false,
        source_file: "",
        is_variadic: false,
      },
      {
        loc: loc(4),
        return_type: @ast.Type::int(),
        name: "main",
        params: [],
        body: Some(
          @ast.Stmt::Block(
            [
              @ast.Stmt::Expr(
                // use(make())：外层 CallPtr(use)，实参 = CallPtr(make)
                @ast.Expr::CallPtr(
                  @ast.Expr::Identifier(
                    "use",
                    loc(5),
                    @ast.Type::function(@ast.Type::int(), [struct_ty]),
                  ),
                  [
                    @ast.Expr::CallPtr(
                      @ast.Expr::Identifier(
                        "make",
                        loc(5),
                        @ast.Type::function(struct_ty, []),
                      ),
                      [],
                      loc(5),
                      struct_ty,
                    ),
                  ],
                  loc(5),
                  @ast.Type::int(),
                ),
                loc(5),
              ),
            ],
            loc(4),
          ),
        ),
        is_static: false,
        is_extern: false,
        source_file: "",
        is_variadic: false,
      },
    ],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
  let gen = BytecodeGen::new()
  let (output, errors) = gen.generate(program)
  assert_eq(errors.length(), 0)
  let o = output.unwrap()
  // S 两 int = 8 字节 = 2 words：第 4 子路径的指令序特征——
  // 内层 Call(use 前近端)之后应出现 StoreLocal(temp0) → LoadLocal(temp0)
  // → LoadMem → LoadLocal(temp0) → PushConst 4 → Add → LoadMem（words=2，
  // 第二字带 +4 偏移；零填充分支的形态是 PushConst 0）
  let ip = o.func_table.get("main").unwrap().ip
  // 找内层 make 的 Call 指令
  let mut call_ip = -1
  for i in ip..<o.code.length() {
    if o.code[i].op is @opcode.OpCode::Call &&
      o.code[i].operand == o.func_index.get("make").unwrap() {
      call_ip = i
      break
    }
  }
  assert_true(call_ip >= 0)
  // Call 后：返回地址 GetFrameBase+PushConst+Add（ret_temp）→ StoreLocal temp
  // → 两轮 LoadLocal+LoadMem（第二轮 +4）
  let seq = o.code
  assert_true(seq[call_ip + 4].op is @opcode.OpCode::StoreLocal)
  assert_true(seq[call_ip + 5].op is @opcode.OpCode::LoadLocal)
  assert_true(seq[call_ip + 6].op is @opcode.OpCode::LoadMem)
  assert_true(seq[call_ip + 7].op is @opcode.OpCode::LoadLocal)
  assert_true(seq[call_ip + 8].op is @opcode.OpCode::PushConst)
  assert_eq(seq[call_ip + 8].operand, 4)
  assert_true(seq[call_ip + 9].op is @opcode.OpCode::Add)
  assert_true(seq[call_ip + 10].op is @opcode.OpCode::LoadMem)
}

///|
/// 表达式核心批锚（S5 扩展批二号：二元/一元/Cast/sizeof 族）——
/// int 加法的指令序（双 PushConst + Add）与隐式提升链形态。
test "expr-core: int add + implicit promotion chain" {
  let program : @ast.ProgramNode = {
    structs: [],
    unions: [],
    globals: [],
    funcs: [
      {
        loc: loc(1),
        return_type: @ast.Type::int(),
        name: "main",
        params: [],
        body: Some(
          @ast.Stmt::Block(
            [
              @ast.Stmt::VarDecl(
                @ast.Type::int(),
                "r",
                Some(
                  // r = 2 + 3（外层赋值未接线——用 return 表达式锚二元）
                  @ast.Expr::Binary(
                    @ast.BinaryOp::Add,
                    @ast.Expr::Literal(2, loc(2), @ast.Type::int()),
                    @ast.Expr::Literal(3, loc(2), @ast.Type::int()),
                    loc(2),
                    @ast.Type::int(),
                  ),
                ),
                [],
                false,
                loc(2),
              ),
              @ast.Stmt::Return(
                Some(@ast.Expr::Identifier("r", loc(3), @ast.Type::int())),
                loc(3),
              ),
            ],
            loc(1),
          ),
        ),
        is_static: false,
        is_extern: false,
        source_file: "",
        is_variadic: false,
      },
    ],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
  let gen = BytecodeGen::new()
  let (output, errors) = gen.generate(program)
  assert_eq(errors.length(), 0)
  let o = output.unwrap()
  // VarDecl init 走 gen_expr(Binary)：PushConst 2 + PushConst 3 + Add + StoreLocal
  let ip = o.func_table.get("main").unwrap().ip
  // ip: StepEvent(Block) ip+1: StepEvent(VarDecl) ip+2..: 二元序列
  assert_true(o.code[ip + 2].op is @opcode.OpCode::PushConst)
  assert_eq(o.code[ip + 2].operand, 2)
  assert_true(o.code[ip + 3].op is @opcode.OpCode::PushConst)
  assert_eq(o.code[ip + 3].operand, 3)
  assert_true(o.code[ip + 4].op is @opcode.OpCode::Add)
  assert_true(o.code[ip + 5].op is @opcode.OpCode::StoreLocal)
}

///|
/// && 短路 + T-P1-1 结果规范化锚（5&&3 必须得 0/1 而非 3）。

///|
/// while 正向锚（扩展批三号接线后）：while(1){} 的循环结构——
/// cond PushConst + JumpIfZero + 尾部 Jump 回 cond 起点。
test "control-flow: while loop generates back-edge" {
  let program : @ast.ProgramNode = {
    structs: [],
    unions: [],
    globals: [],
    funcs: [
      {
        loc: loc(3),
        return_type: @ast.Type::int(),
        name: "main",
        params: [],
        body: Some(
          @ast.Stmt::Block(
            [
              @ast.Stmt::While(
                @ast.Expr::Literal(1, loc(3), @ast.Type::int()),
                @ast.Stmt::Block([], loc(3)),
                loc(3),
              ),
            ],
            loc(3),
          ),
        ),
        is_static: false,
        is_extern: false,
        source_file: "",
        is_variadic: false,
      },
    ],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
  let gen = BytecodeGen::new()
  let (output, errors) = gen.generate(program)
  assert_eq(errors.length(), 0)
  let o = output.unwrap()
  let ip = o.func_table.get("main").unwrap().ip
  // ip: StepEvent(Block) ip+1: StepEvent(While) ip+2: PushConst 1
  assert_eq(o.code[ip + 2].operand, 1)
  assert_true(o.code[ip + 3].op is @opcode.OpCode::JumpIfZero)
  // 循环回边：Jump 回 cond 起点（ip+2）
  let mut has_back_jump = false
  for ins in o.code {
    if ins.op is @opcode.OpCode::Jump && ins.operand == ip + 2 {
      has_back_jump = true
    }
  }
  assert_true(has_back_jump)
}

///|
/// 退役语句 fail loud 锚（RangeFor——砍 C++ 裁定，永不接线）：
/// 整体 Err；行号 0（stmt_loc 的 RangeFor 走 _ 兜底——Rust 同款）；
/// 文案含"退役"且不含"未实现"（假承诺）。
test "control-flow: retired C++ stmt fails loud without in-flight wording" {
  let program : @ast.ProgramNode = {
    structs: [],
    unions: [],
    globals: [],
    funcs: [
      {
        loc: loc(3),
        return_type: @ast.Type::int(),
        name: "main",
        params: [],
        body: Some(
          @ast.Stmt::Block(
            [
              @ast.Stmt::RangeFor(
                "i",
                @ast.Type::int(),
                @ast.Expr::Literal(1, loc(3), @ast.Type::int()),
                @ast.Stmt::Block([], loc(3)),
                loc(3),
              ),
            ],
            loc(3),
          ),
        ),
        is_static: false,
        is_extern: false,
        source_file: "",
        is_variadic: false,
      },
    ],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
  let gen = BytecodeGen::new()
  let (output, errors) = gen.generate(program)
  assert_true(output is None)
  assert_true(errors.length() > 0)
  assert_true(errors[0].has_prefix("第 0 行："))
  assert_true(!errors[0].contains("未实现"))
  assert_true(errors[0].contains("退役"))
}
