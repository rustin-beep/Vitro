///|
/// codegen 骨架白盒测试（S5 开工批）——手工构造 AST（不经 parser，
/// 同 typeck 白盒先例）走 generate 全流程，锚定骨架通路不变量：
/// Pass 1 全局布局（libc 预留段起点 / 标量位模式 / 字符串回填）、
/// Pass 2/3 函数元数据回填、入口 wrapper 形态、global_data_end 口径。
/// 语句/表达式族扩展批接线后逐批补对应锚（红→绿纪律）。
fn loc(line : Int32) -> @source.SourceLoc {
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
        ..Default::default(),
        loc: loc(1),
        ty: @ast.Type::int(),
        name: "g",
        init: Some(@ast.Expr::Literal(42, loc(1), @ast.Type::int())),
      },
    ],
    funcs: [
      {
        ..Default::default(),
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
  // with_mode(false) 预注册：88 - 6（strcpy/strcat/strncpy/memcpy/memmove
  // 分发回 Host——2026-10-06 三函数扩入改判集：负 n 越界写 trap 语义；
  // 2026-10-13 strcmp 扩入（病 45：unsigned char 修复走 Host 侧））
  // = 82 条
  let mut libc_count = 0
  o.func_index.each((_, idx) => {
    if idx >= 1000 && idx <= 1087 {
      libc_count += 1
    }
  })
  assert_eq(libc_count, 82)
  // strcpy/strcat/strncpy/memcpy/memmove 不预注册（Host 路径带 E3070
  // 栈缓冲区检测 / 负 n trap 教学语义）
  assert_true(o.func_index.get("strcpy") is None)
  assert_true(o.func_index.get("strcat") is None)
  assert_true(o.func_index.get("strncpy") is None)
  assert_true(o.func_index.get("memcpy") is None)
  assert_true(o.func_index.get("memmove") is None)
  assert_true(o.func_index.get("strcmp") is None) // 病 45 改判第 6 名
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
        ..Default::default(),
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
      },
    ],
    funcs: [
      {
        ..Default::default(),
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
        ..Default::default(),
        loc: loc(1),
        ty: @ast.Type::double(),
        name: "g",
        init: Some(@ast.Expr::Literal(1, loc(1), @ast.Type::int())),
      },
    ],
    funcs: [
      {
        ..Default::default(),
        loc: loc(2),
        return_type: @ast.Type::int(),
        name: "main",
        params: [],
        body: Some(@ast.Stmt::Block([], loc(2))),
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
        ..Default::default(),
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
        ..Default::default(),
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
        ..Default::default(),
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
      },
      {
        ..Default::default(),
        loc: loc(2),
        return_type: @ast.Type::int(),
        name: "main",
        params: [],
        body: Some(@ast.Stmt::Block([], loc(2))),
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
        ..Default::default(),
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
        ..Default::default(),
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
        is_forward: false,
      },
    ],
    unions: [],
    globals: [],
    funcs: [
      {
        ..Default::default(),
        loc: loc(2),
        return_type: struct_ty,
        name: "make",
        params: [],
        body: Some(@ast.Stmt::Block([], loc(2))),
      },
      {
        ..Default::default(),
        loc: loc(3),
        return_type: @ast.Type::int(),
        name: "use",
        params: [{ ty: struct_ty, name: "s", loc: loc(3), default: None, }],
        body: Some(@ast.Stmt::Block([], loc(3))),
      },
      {
        ..Default::default(),
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
        ..Default::default(),
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
        ..Default::default(),
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
        ..Default::default(),
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

///|
/// #76 缺口 4 锚（2026-10-13）：文件作用域指定初始化器——数组标量目标的
/// Index designator 按 C11 6.7.9 稀疏展开（`int a[8] = {[2]=7,[5]=9}` →
/// a[2]=7/a[5]=9 其余零初始化）。修复前 codegen fail loud 拒绝（无码出口
/// ——#38 登记的「codegen 错误无诊断码」活体）；块作用域同写法本就通过。
test "skeleton: global designated initializer index sparse fill" {
  let gen = BytecodeGen::new()
  let program : @ast.ProgramNode = {
    structs: [],
    unions: [],
    globals: [
      {
        ..Default::default(),
        loc: loc(1),
        ty: @ast.Type::array_of(@ast.Type::int(), [8]),
        name: "a",
        init: Some(
          @ast.Expr::InitList(
            [
              {
                designators: [
                  @ast.Designator::Index(
                    @ast.Expr::Literal(2, loc(1), @ast.Type::int()),
                  ),
                ],
                value: @ast.Expr::Literal(7, loc(1), @ast.Type::int()),
              },
              {
                designators: [
                  @ast.Designator::Index(
                    @ast.Expr::Literal(5, loc(1), @ast.Type::int()),
                  ),
                ],
                value: @ast.Expr::Literal(9, loc(1), @ast.Type::int()),
              },
            ],
            loc(1),
            @ast.Type::void_type(),
          ),
        ),
      },
    ],
    funcs: [
      {
        ..Default::default(),
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
      },
    ],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
  let (output, errors) = gen.generate(program)
  assert_eq(errors.length(), 0, msg="designated 全局不应再 fail loud")
  let o = output.unwrap()
  // 稀疏填充（GLOBAL_START 预留 1024 后）：a[2]@1032=7 / a[5]@1044=9，
  // 其余元素零初始化不产生写记录（静态零语义）
  assert_eq(
    o.globals_init_32,
    [(1032U, 7), (1044U, 9)],
    msg="Index designator 按下标稀疏落位",
  )
}

///|
/// #153：flatten_init_list 对超 int32 的常量不再上报——范围判断发生在
/// 无目标类型上下文里（long long → unsigned int 的隐式转换合法，
/// typeck check_assignable 已放行），上报与全局标量路径 LongLiteral
/// `value.to_int()` 位模式截断语义（var_decl.mbt:300）自相矛盾。
/// i32 位模式断言：4294967295 → -1、-4294967295 → 1（模 2^32 = C 转换语义）。
test "flatten_init_list_no_int_range_reject" {
  let lloc = @source.SourceLoc::new(1, 1)
  let elems : Array[@ast.InitElement] = [
    {
      designators: [],
      value: @ast.Expr::LongLiteral(
        4294967295L,
        lloc,
        @ast.Type::unsigned_int(),
      ),
    },
    {
      designators: [],
      value: @ast.Expr::Unary(
        @ast.UnaryOp::Neg,
        @ast.Expr::LongLiteral(
          4294967295L,
          lloc,
          @ast.Type::LongLong(false, false),
        ),
        lloc,
        @ast.Type::LongLong(false, false),
      ),
    },
  ]
  let errors : Array[String] = []
  let values = flatten_init_list(elems, errors)
  assert_eq(
    errors.length(),
    0,
    msg="unsigned 域常量不应在无类型上下文被拒",
  )
  assert_eq(values.length(), 2, msg="两元素均应落值")
  assert_eq(values[0], -1, msg="4294967295 的 i32 位模式是 -1")
  assert_eq(values[1], 1, msg="-4294967295 模 2^32 = 1")
}

///|
/// #162（2026-10-18 审阅批 P3-2 补锚）：struct 数组元素按值实参——
/// gen_index 对 struct 结果**不 load 留地址**，gen_call_ptr 兜底臂从
/// 地址逐字拷贝。突变区分锚：main 里 `asum(arr2[0])` 的 LoadMem 计数
/// 恰 = struct 字数（16B=4 words 的逐字 LoadMem）；旧病（gen_index 对
/// struct 照发 4 字节 LoadMem 留首字段值）多 1 个 = 5，反向突变立红。
test "skeleton: struct array elem byval arg leaves address (#162)" {
  let loc = @source.SourceLoc::new(2, 5)
  // struct A { int arr[3]; int n; }
  let decl_a : @ast.StructDecl = {
    ..Default::default(),
    loc,
    name: "A",
    fields: [
      { ty: @ast.Type::array_of(@ast.Type::int(), [3]), name: "arr", },
      { ty: @ast.Type::int(), name: "n", },
    ],
  }
  // int asum(struct A a) —— 存根（签名进 func_table 即可）
  let asum : @ast.FuncDecl = {
    ..Default::default(),
    loc,
    return_type: @ast.Type::int(),
    name: "asum",
    params: [
      { ty: @ast.Type::struct_type("A"), name: "a", loc, default: None, },
    ],
    body: Some(@ast.Stmt::Block([], loc)),
    source_file: "t.c",
  }
  // struct A arr2[2]; —— 全局（数组元素 struct 形态）
  let arr2 : @ast.GlobalDecl = {
    ..Default::default(),
    loc,
    ty: @ast.Type::array_of(@ast.Type::struct_type("A"), [2]),
    name: "arr2",
  }
  // main：asum(arr2[0]);
  let call : @ast.Stmt = @ast.Stmt::Expr(
    @ast.Expr::CallPtr(
      @ast.Expr::Identifier("asum", loc, @ast.Type::void_type()),
      [
        @ast.Expr::Index(
          @ast.Expr::Identifier(
            "arr2",
            loc,
            @ast.Type::array_of(@ast.Type::struct_type("A"), [2]),
          ),
          @ast.Expr::Literal(0, loc, @ast.Type::int()),
          loc,
          @ast.Type::struct_type("A"),
        ),
      ],
      loc,
      @ast.Type::int(),
    ),
    loc,
  )
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc,
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(@ast.Stmt::Block([call, @ast.Stmt::Return(None, loc)], loc)),
    source_file: "t.c",
  }
  let gen = BytecodeGen::new()
  let (output, errors) = gen.generate({
    structs: [decl_a],
    unions: [],
    globals: [arr2],
    funcs: [asum, main],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_eq(errors.length(), 0)
  let o = output.unwrap()
  // main 体（含 asume 调用）的 LoadMem 计数：struct A = 16B = 4 words
  // ——恰好兜底臂的 4 个逐字 LoadMem；gen_index 若对 struct 结果多发
  // 一个 LoadMem（旧病）= 5
  let main_meta = o.func_table.get("main").unwrap()
  let body_ip = main_meta.ip
  let body_len = 32 // Block+Expr+Return 段（防御上界——计数遍历窗口）
  let mut loadmem_count = 0
  for i in body_ip..<(body_ip + body_len) {
    if i < o.code.length() && o.code[i].op is @opcode.OpCode::LoadMem {
      loadmem_count += 1
    }
  }
  assert_eq(
    loadmem_count,
    4,
    msg="struct 元素实参 = 4 words 逐字 LoadMem（gen_index 对 struct 不 load——多 1 即旧病复发）",
  )
}

///|
/// #193 回归锚（2026-10-21 审阅补）：`elem_type_size` 返回的是**基元宽度**
/// （stride = 基元宽 × 维度数）——`char (*p)[8]` 必须是 1，不是 `_ => 4`
/// 兜底下的 4（后者乘 8 维得 stride 32，实测指令流 PushConst 32）。
///
/// 为何要单独立锚：把 `TK_Array => self.elem_type_size(elem_type)` 还原成
/// 缺陷版 `TK_Array => 4` 后，本包单测 18/18 与 codegen_diff 四套件
/// （472/80/138/20）全绿——语料只有 `int(*)[N]`（基元 4 碰巧正确），
/// `char(*)[N]` 零覆盖，五家 digest 与运行期对拍都抓不到该回退。
test "elem_type_size_pointer_to_array_stride_issue193" {
  let gen = BytecodeGen::new()
  // char (*p)[8] —— 本条修复的原始形态；基元 = char 1 字节
  let char_row = @ast.Type::array_of(@ast.Type::char(), [8])
  assert_eq(
    gen.elem_type_size(@ast.Type::pointer_to(char_row)),
    1,
    msg="char(*)[8] 基元应为 1（缺陷版落 4 → stride 32）",
  )
  // int (*p)[3] —— 旧版碰巧正确（基元 4 → stride 12），锁住不回归
  let int_row = @ast.Type::array_of(@ast.Type::int(), [3])
  assert_eq(
    gen.elem_type_size(@ast.Type::pointer_to(int_row)),
    4,
    msg="int(*)[3] 基元应为 4",
  )
  // char **p —— pointee 是指针（4 字节），不得继续下钻成 1
  assert_eq(
    gen.elem_type_size(
      @ast.Type::pointer_to(@ast.Type::pointer_to(@ast.Type::char())),
    ),
    4,
    msg="char** 基元应是指针宽 4（误下钻会落 1）",
  )
  // char *p —— pointee 是标量 char
  assert_eq(
    gen.elem_type_size(@ast.Type::pointer_to(@ast.Type::char())),
    1,
    msg="char* 基元应为 1",
  )
}

///|
/// #193 端到端产物锚：`char (*p)[8]` 的 `p[1]` 索引——gen_index 以
/// compute_stride(char[8], elem_type_size=1) 发 PushConst 8；缺陷版
/// （`TK_Array => 4` 兜底）发 PushConst 32（4×8）。单元锚锁函数语义，
/// 本锚锁 gen_index→elem_type_size 的接线面（防调用点换道绕过单元锚）。
test "skeleton: char-ptr-to-array index stride emits 8 (#193 end-to-end)" {
  let loc = @source.SourceLoc::new(2, 5)
  let row_ty = @ast.Type::array_of(@ast.Type::char(), [8])
  let p_idx : @ast.Stmt = @ast.Stmt::Expr(
    @ast.Expr::Index(
      @ast.Expr::Identifier("p", loc, @ast.Type::pointer_to(row_ty)),
      @ast.Expr::Literal(1, loc, @ast.Type::int()),
      loc,
      row_ty,
    ),
    loc,
  )
  let f : @ast.FuncDecl = {
    ..Default::default(),
    loc,
    return_type: @ast.Type::void_type(),
    name: "f",
    params: [
      { ty: @ast.Type::pointer_to(row_ty), name: "p", loc, default: None, },
    ],
    body: Some(@ast.Stmt::Block([p_idx, @ast.Stmt::Return(None, loc)], loc)),
    source_file: "t.c",
  }
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc,
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(@ast.Stmt::Block([@ast.Stmt::Return(None, loc)], loc)),
    source_file: "t.c",
  }
  let gen = BytecodeGen::new()
  let (output, errors) = gen.generate({
    structs: [],
    unions: [],
    globals: [],
    funcs: [f, main],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_eq(errors.length(), 0)
  let o = output.unwrap()
  let f_meta = o.func_table.get("f").unwrap()
  let body_len = 32 // 防御上界——计数遍历窗口（#162 同款形态）
  let mut has_stride8 = false
  let mut has_stride32 = false
  for i in f_meta.ip..<(f_meta.ip + body_len) {
    if i < o.code.length() && o.code[i].op is @opcode.OpCode::PushConst {
      if o.code[i].operand == 8 {
        has_stride8 = true
      }
      if o.code[i].operand == 32 {
        has_stride32 = true
      }
    }
  }
  assert_true(
    has_stride8,
    msg="char(*)[8] 的 p[1] 索引须发 stride=8（基元 1×维度 8）",
  )
  assert_true(
    !has_stride32,
    msg="出现 stride=32 即缺陷版复发（TK_Array 兜底 4 → 4×8）",
  )
}

///|
/// #201-B 回归锚（2026-10-21）：全局函数指针数组初始化器（`static AF
/// fns[3] = {a1, a1, a1}`）——数组逐元素路径的 flatten_init_list 只折叠
/// 字面量，函数名元素静默落 0（判空恒假 + CallPtr「索引 0 越界」TRAP；
/// 全局标量臂 `AF g = a1` 走 func_index 编码一直正确——形状矩阵三对一
/// 错）。锚断言 fns 三槽写入非零函数索引。
test "skeleton: global fn-ptr array init resolves func index (#201)" {
  let a1 : @ast.FuncDecl = {
    ..Default::default(),
    loc: loc(2),
    return_type: @ast.Type::void_type(),
    name: "a1",
    params: [],
    body: Some(@ast.Stmt::Block([], loc(3))),
    source_file: "t.c",
  }
  let af_ty = @ast.Type::pointer_to(
    @ast.Type::function(@ast.Type::void_type(), []),
  )
  let fns : @ast.GlobalDecl = {
    ..Default::default(),
    loc: loc(4),
    ty: @ast.Type::array_of(af_ty, [3]),
    name: "fns",
    init: Some(
      @ast.Expr::InitList(
        [
          {
            designators: [],
            value: @ast.Expr::Identifier("a1", loc(4), af_ty),
          },
          {
            designators: [],
            value: @ast.Expr::Identifier("a1", loc(4), af_ty),
          },
          {
            designators: [],
            value: @ast.Expr::Identifier("a1", loc(4), af_ty),
          },
        ],
        loc(4),
        af_ty,
      ),
    ),
  }
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc: loc(5),
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(
      @ast.Stmt::Block(
        [
          @ast.Stmt::Return(
            Some(@ast.Expr::Literal(0, loc(5), @ast.Type::int())),
            loc(5),
          ),
        ],
        loc(5),
      ),
    ),
    source_file: "t.c",
  }
  let gen = BytecodeGen::new()
  let (output, errors) = gen.generate({
    structs: [],
    unions: [],
    globals: [fns],
    funcs: [a1, main],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_eq(errors.length(), 0)
  let o = output.unwrap()
  // fns 槽从全局区首（1024）起，3 元素 × 4 字节；每槽须为非零函数索引
  //（a1 编码值与函数表布局相关，锁「非零且一致」两性质）
  let slots = o.globals_init_32.filter(e => e.0 >= 1024U && e.0 < 1024U + 12U)
  assert_eq(
    slots.length(),
    3,
    msg="fns 三槽各须恰有一条全局初始化写记录",
  )
  for s in slots {
    assert_true(
      s.1 != 0,
      msg="函数指针元素不得落 0（#201-B：判空恒假 + CallPtr 越界）",
    )
  }
  assert_eq(slots[0].1, slots[1].1)
  assert_eq(slots[1].1, slots[2].1)
}

///|
/// #205 定性勘误后的残留面（2026-10-21）：纯函数原型声明（无定义体）
/// 被调用时的错误类别。clang `-c` 接受声明（链接才报 undefined）；Vitro
/// 一体化编译的如实形态 = 「已声明但未定义」——旧文案「未声明的标识符」
/// 是谎报（声明明明在场，#202 修复验收时被误读为 include 缺口，实为
/// 本缺口与 include 无关：磁盘/文本直写同病）。
test "skeleton: call to declared-but-undefined fn reports honest error (#205)" {
  let decl_f : @ast.FuncDecl = {
    ..Default::default(),
    loc: loc(1),
    return_type: @ast.Type::int(),
    name: "f",
    params: [],
    body: None, // 纯原型声明（`int f(void);`）
    source_file: "t.c",
  }
  let call_f : @ast.Stmt = @ast.Stmt::Expr(
    @ast.Expr::CallPtr(
      @ast.Expr::Identifier(
        "f",
        loc(2),
        @ast.Type::function(@ast.Type::int(), []),
      ),
      [],
      loc(2),
      @ast.Type::int(),
    ),
    loc(2),
  )
  let call_g : @ast.Stmt = @ast.Stmt::Expr(
    @ast.Expr::CallPtr(
      @ast.Expr::Identifier(
        "g",
        loc(2),
        @ast.Type::function(@ast.Type::int(), []),
      ),
      [],
      loc(2),
      @ast.Type::int(),
    ),
    loc(2),
  )
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc: loc(2),
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(
      @ast.Stmt::Block(
        [
          call_f,
          call_g,
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
  let gen = BytecodeGen::new()
  let (_, errors) = gen.generate({
    structs: [],
    unions: [],
    globals: [],
    funcs: [decl_f, main],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  let joined = errors.join("\n")
  assert_true(
    joined.contains("已声明但未定义"),
    msg="裸原型被调用须报「已声明但未定义」（旧文案谎报「未声明的标识符」）",
  )
  assert_true(
    !joined.contains("'f' 未声明") &&
    !joined.contains("未声明的标识符 'f'"),
    msg="f 有声明在场，不得再报「未声明的标识符」",
  )
  assert_true(
    joined.contains("未声明的标识符 'g'"),
    msg="完全未声明的 g 维持「未声明的标识符」类别（对照臂）",
  )
}

///|
/// #238 红锚（2026-10-21 千行语料 llm_scale_shell.c 暴露）：`(void)expr;`
/// 表达式语句栈泄漏——`gen_cast_expr` 对 TK_Void 目标求值后不弹栈，而
/// `gen_expr_stmt` 按 `ty.kind() is TK_Void` 判「无需 Pop」⇒ 值永久留在
/// 栈上。函数栈不守恒（#200 验证器 stack-unbalanced-ret 实测净增 = (void)
/// 个数）；循环体内则无界涨栈。千行语料三次命中（ls/env/exit 三函数 2+2+4）。
test "skeleton: cast-to-void expr stmt keeps stack balanced (#238)" {
  let void_ty = @ast.Type::void_type()
  let param_ty = @ast.Type::pointer_to(@ast.Type::char())
  // 函数体：(void)p; (void)p; return 0;
  let discard : @ast.Expr = @ast.Expr::Cast(
    @ast.Expr::Identifier("p", loc(2), param_ty),
    void_ty,
    loc(2),
    void_ty,
  )
  let body : @ast.Stmt = @ast.Stmt::Block(
    [
      @ast.Stmt::Expr(discard, loc(2)),
      @ast.Stmt::Expr(discard, loc(3)),
      @ast.Stmt::Return(
        Some(@ast.Expr::Literal(0, loc(4), @ast.Type::int())),
        loc(4),
      ),
    ],
    loc(2),
  )
  let f : @ast.FuncDecl = {
    ..Default::default(),
    loc: loc(1),
    return_type: @ast.Type::int(),
    name: "f",
    params: [{ ty: param_ty, name: "p", loc: loc(1), default: None, }],
    body: Some(body),
    source_file: "t.c",
  }
  let main : @ast.FuncDecl = {
    ..Default::default(),
    loc: loc(5),
    return_type: @ast.Type::int(),
    name: "main",
    params: [],
    body: Some(@ast.Stmt::Block([@ast.Stmt::Return(None, loc(5))], loc(5))),
    source_file: "t.c",
  }
  let gen = BytecodeGen::new()
  let (output, errors) = gen.generate({
    structs: [],
    unions: [],
    globals: [],
    funcs: [f, main],
    classes: [],
    templates: [],
    template_instantiations: [],
  })
  assert_eq(errors.length(), 0)
  let o = output.unwrap()
  let violations = @bytecode.verify_compile_output(o, false)
  assert_true(
    violations.is_empty(),
    msg="(void)expr; 不得泄漏栈（#200 验证器：\{violations.length()} 条违约——首条 \{@bytecode.verify_violations_json(violations)}）",
  )
}

///|
/// #283 审阅 P1 补锚（PR #299，2026-10-25）：gen_addr Identifier 臂解析序
/// local → static → global 的白盒直锚。该臂可达面极窄——运行期 `&x` 取址走
/// unary Addr 臂、指针初始化器走 init 回填，语料与定向探针均无观察差异
///（PR #299 审阅指令流差分 + 本批多形态探针双重实证），黑盒锚锁不住，
/// 故白盒锁序防回退：同名 static local 与 global 双在表时 static 须抢先
///（旧序 global 抢先）。
test "wb gen_addr resolution order static before global (#283 review P1)" {
  let gen = BytecodeGen::new()
  // 同名双注册：static 槽偏移 8、global 槽偏移 100；local 表在但不命中
  gen.static_local_indices.set("c", 8)
  gen.static_local_types.set("c", @ast.Type::Pointer(@ast.Type::int(), false))
  gen.global_indices.set("c", 100)
  gen.global_types.set("c", @ast.Type::int())
  gen.local_indices.set("other", 4)
  gen.local_types.set("other", @ast.Type::int())
  let loc = @source.SourceLoc::new(1, 1)
  let n0 = gen.code.length()
  gen.gen_addr(@ast.Expr::Identifier("c", loc, @ast.Type::int()), loc)
  // static 命中：恰一条 PushConst(GLOBAL_START + 8)——无 GetFrameBase
  //（local 命中形态是三指令 GetFrameBase/PushConst/Add），且偏移绝非
  // global 槽（GLOBAL_START + 100）
  assert_eq(
    gen.code.length() - n0,
    1,
    msg="static 命中应恰 emit 一条 PushConst（多指令=误走 local 通路）",
  )
  let instr = gen.code[gen.code.length() - 1]
  assert_true(instr.op is @opcode.OpCode::PushConst, msg="须为 PushConst")
  assert_eq(
    instr.operand,
    @bytecode.GLOBAL_START.reinterpret_as_int() + 8,
    msg="偏移须取 static 槽（8）——取 100 即 global 抢先（#283 回退）",
  )
}

///|
/// 对照臂：仅 global 在表（无 static）时 gen_addr 走 global 槽——static
/// 前置不得外溢吞掉合法 global 取址。
test "wb gen_addr global fallback intact (#283 review P1)" {
  let gen = BytecodeGen::new()
  gen.global_indices.set("g", 60)
  gen.global_types.set("g", @ast.Type::int())
  let loc = @source.SourceLoc::new(1, 1)
  let n0 = gen.code.length()
  gen.gen_addr(@ast.Expr::Identifier("g", loc, @ast.Type::int()), loc)
  assert_eq(gen.code.length() - n0, 1, msg="global 命中恰一条 PushConst")
  let instr = gen.code[gen.code.length() - 1]
  assert_true(instr.op is @opcode.OpCode::PushConst)
  assert_eq(
    instr.operand,
    @bytecode.GLOBAL_START.reinterpret_as_int() + 60,
    msg="无 static 时取 global 槽（60）",
  )
}
