///|
/// #426 B3' 批 5：codegen 域判定对拍锚（防 D2 漂移——设计单 §二·4）。
/// codegen/binary.mbt 的 is_unsigned/unsigned_q/op_is_long_long 判据与
/// typeck promote_type（D1）是**双轨实现**（各自独立推导、语义一致）；
/// typeck 与 VM 已接共享核（批 1/3），D2 不重写只加本锚组：同表达式族
/// 断言**实际发射的 opcode 族** == 按核 common_domain 推导的期望族——
/// 未来任一侧漂移（判据改坏 / 核语义改坏）即红。
/// 纯增锚锁当前正确行为（M08 A1/A2 真值形态），无红→绿义务（非缺陷修复）。

///|
/// minimal_program 的 return 表达式参数化版（main 体仅一条 return e）。
fn minimal_program_with_return(e : @ast.Expr) -> @ast.ProgramNode {
  {
    structs: [],
    unions: [],
    globals: [],
    funcs: [
      {
        ..Default::default(),
        loc: loc(2),
        return_type: @ast.Type::int(),
        name: "main",
        params: [],
        body: Some(
          @ast.Stmt::Block([@ast.Stmt::Return(Some(e), loc(2))], loc(2)),
        ),
      },
    ],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
}

///|
/// 取 main 函数体的 opcode 切片（body_ip 起，至首个 Ret 止——不含 wrapper）。
fn main_body_ops(output : @bytecode.CompileOutput) -> Array[@opcode.OpCode] {
  let meta = output.func_table.get("main").unwrap()
  let ops : Array[@opcode.OpCode] = []
  let mut i = meta.ip
  while i < output.code.length() {
    let op = output.code[i].op
    if op is @opcode.OpCode::Ret {
      break
    }
    ops.push(op)
    i += 1
  }
  ops
}

///|
/// `2LL / 3u` → **DivQ**（公共域 = common_domain(I64, U32) = I64 有符号——
/// i64 容纳 u32 全值域；A1 真值形态 0 的发射面；若 D2 漂回「任一侧
/// unsigned 即无符号」将发射 UDivQ 即红）
test "parity_div_ll_uint_emits_divq" {
  let ll = @ast.Type::long_long()
  let prog = minimal_program_with_return(
    @ast.Expr::Binary(
      @ast.BinaryOp::Div,
      @ast.Expr::LongLiteral(2L, loc(3), ll),
      @ast.Expr::Literal(3, loc(3), @ast.Type::unsigned_int()),
      loc(3),
      ll,
    ),
  )
  let gen = BytecodeGen::new()
  let (output, errors) = gen.generate(prog)
  assert_eq(errors.length(), 0)
  let ops = main_body_ops(output.unwrap())
  assert_true(
    ops.exists(op => op is @opcode.OpCode::DivQ),
    msg="2LL/3u 期望 DivQ（公共域 I64 有符号）",
  )
  assert_false(
    ops.exists(op => op is @opcode.OpCode::UDivQ),
    msg="不应发射 UDivQ（u32 参与不升无符号 LL 域）",
  )
  assert_false(
    ops.exists(op => op is @opcode.OpCode::Div),
    msg="不应发射 32 位 Div",
  )
}

///|
/// `(unsigned char)200 / 3` → **Div**（uchar 提升 signed int——A1 真值形态
/// -200 的发射面；D2 比较面已正确豁免 char 级 unsigned，算术面经结果类型
/// int 间接同义）
test "parity_div_uchar_int_emits_div" {
  let uchar = @ast.Type::Char(true, false)
  let prog = minimal_program_with_return(
    @ast.Expr::Binary(
      @ast.BinaryOp::Div,
      @ast.Expr::Cast(
        @ast.Expr::Literal(200, loc(3), @ast.Type::int()),
        uchar,
        loc(3),
        uchar,
      ),
      @ast.Expr::Literal(3, loc(3), @ast.Type::int()),
      loc(3),
      @ast.Type::int(),
    ),
  )
  let gen = BytecodeGen::new()
  let (output, errors) = gen.generate(prog)
  assert_eq(errors.length(), 0)
  let ops = main_body_ops(output.unwrap())
  assert_true(
    ops.exists(op => op is @opcode.OpCode::Div),
    msg="(uchar)200/3 期望 Div（提升 signed int）",
  )
  assert_false(
    ops.exists(op => op is @opcode.OpCode::UDiv),
    msg="不应发射 UDiv（uchar 的 unsigned 位随提升消失）",
  )
}

///|
/// `-1 < 1u` → **ULt**（比较面 TK_Int 级 unsigned 参与判据——A2 同族真值
/// 形态（-1==4294967295u 为 1）的发射面）
test "parity_cmp_int_uint_emits_ult" {
  let prog = minimal_program_with_return(
    @ast.Expr::Binary(
      @ast.BinaryOp::Lt,
      @ast.Expr::Unary(
        @ast.UnaryOp::Neg,
        @ast.Expr::Literal(1, loc(3), @ast.Type::int()),
        loc(3),
        @ast.Type::int(),
      ),
      @ast.Expr::Literal(1, loc(3), @ast.Type::unsigned_int()),
      loc(3),
      @ast.Type::int(),
    ),
  )
  let gen = BytecodeGen::new()
  let (output, errors) = gen.generate(prog)
  assert_eq(errors.length(), 0)
  let ops = main_body_ops(output.unwrap())
  assert_true(
    ops.exists(op => op is @opcode.OpCode::ULt),
    msg="-1<1u 期望 ULt",
  )
  assert_false(
    ops.exists(op => op is @opcode.OpCode::Lt),
    msg="不应发射有符号 Lt（uint 参与升无符号比较域）",
  )
}

///|
/// `2LL >> 1u` → **ShrQ** / `2ULL >> 1u` → **LShrQ**（Shr 域随**左操作数**
/// 提升后类型——C11 §6.5.7；A1 真值形态 -1LL>>1u = -1 的发射面）
test "parity_shr_domain_follows_left_operand" {
  fn shr_prog(left : @ast.Expr, ty : @ast.Type) -> @ast.ProgramNode {
    minimal_program_with_return(
      @ast.Expr::Binary(
        @ast.BinaryOp::Shr,
        left,
        @ast.Expr::Literal(1, loc(3), @ast.Type::unsigned_int()),
        loc(3),
        ty,
      ),
    )
  }
  let ull = @ast.Type::LongLong(true, false)
  // signed LL：算术右移
  let gen = BytecodeGen::new()
  let (o1, e1) = gen.generate(
    shr_prog(
      @ast.Expr::LongLiteral(2L, loc(3), @ast.Type::long_long()),
      @ast.Type::long_long(),
    ),
  )
  assert_eq(e1.length(), 0)
  let ops1 = main_body_ops(o1.unwrap())
  assert_true(
    ops1.exists(op => op is @opcode.OpCode::ShrQ),
    msg="2LL>>1u 期望 ShrQ（算术）",
  )
  assert_false(
    ops1.exists(op => op is @opcode.OpCode::LShrQ),
    msg="不应逻辑右移",
  )
  // ULL：逻辑右移
  let gen2 = BytecodeGen::new()
  let (o2, e2) = gen2.generate(
    shr_prog(@ast.Expr::LongLiteral(2L, loc(3), ull), ull),
  )
  assert_eq(e2.length(), 0)
  let ops2 = main_body_ops(o2.unwrap())
  assert_true(
    ops2.exists(op => op is @opcode.OpCode::LShrQ),
    msg="2ULL>>1u 期望 LShrQ（逻辑）",
  )
  assert_false(
    ops2.exists(op => op is @opcode.OpCode::ShrQ),
    msg="不应算术右移",
  )
}

///|
/// `2ULL / 3u` → **UDivQ**（公共域 = common_domain(U64, U32) = U64 无符号
/// ——病 34 修复形态的发射面锁定）
test "parity_div_ull_emits_udivq" {
  let ull = @ast.Type::LongLong(true, false)
  let prog = minimal_program_with_return(
    @ast.Expr::Binary(
      @ast.BinaryOp::Div,
      @ast.Expr::LongLiteral(2L, loc(3), ull),
      @ast.Expr::Literal(3, loc(3), @ast.Type::unsigned_int()),
      loc(3),
      ull,
    ),
  )
  let gen = BytecodeGen::new()
  let (output, errors) = gen.generate(prog)
  assert_eq(errors.length(), 0)
  let ops = main_body_ops(output.unwrap())
  assert_true(
    ops.exists(op => op is @opcode.OpCode::UDivQ),
    msg="2ULL/3u 期望 UDivQ（无符号 64 域）",
  )
  assert_false(
    ops.exists(op => op is @opcode.OpCode::DivQ),
    msg="不应发射 DivQ（符号语义 2^63 域错值——病 34 形态回潮即红）",
  )
}

///|
/// PR #487 审阅 P3-5：m08_consistency 双上下文锚手写指令序列所涉 opcode
/// 的发射面补齐——`-1LL < 1ULL` → **ULtQ**（64 位无符号比较域；g4 变体
/// 锚 `m08c_g4_ull_cmp_domain` 的发射面）。若 codegen 域判定漂移改发
/// 有符号 LtQ，本锚红（vm 侧手写序列不会红——vm_diff golden 兜底前的
/// 第一道）。
test "parity_cmp_ll_ull_emits_ultq" {
  let ll = @ast.Type::long_long()
  let ull = @ast.Type::LongLong(true, false)
  let prog = minimal_program_with_return(
    @ast.Expr::Binary(
      @ast.BinaryOp::Lt,
      @ast.Expr::LongLiteral(-1L, loc(3), ll),
      @ast.Expr::LongLiteral(1L, loc(3), ull),
      loc(3),
      ll,
    ),
  )
  let gen = BytecodeGen::new()
  let (output, errors) = gen.generate(prog)
  assert_eq(errors.length(), 0)
  let ops = main_body_ops(output.unwrap())
  assert_true(
    ops.exists(op => op is @opcode.OpCode::ULtQ),
    msg="-1LL<1ULL 期望 ULtQ（ULL 参与升 64 位无符号比较域）",
  )
  assert_false(
    ops.exists(op => op is @opcode.OpCode::LtQ),
    msg="不应发射有符号 LtQ（2^63 域错判形态回潮即红）",
  )
}

///|
/// P3-5：`1LL << 2u` → **ShlQ**（Q 族左移——移位边界锚
/// `m08c_shl_boundary_62_and_64` 的发射面；Shr 已有 parity 锚，Shl 补位）。
test "parity_shl_ll_emits_shlq" {
  let ll = @ast.Type::long_long()
  let prog = minimal_program_with_return(
    @ast.Expr::Binary(
      @ast.BinaryOp::Shl,
      @ast.Expr::LongLiteral(1L, loc(3), ll),
      @ast.Expr::Literal(2, loc(3), @ast.Type::unsigned_int()),
      loc(3),
      ll,
    ),
  )
  let gen = BytecodeGen::new()
  let (output, errors) = gen.generate(prog)
  assert_eq(errors.length(), 0)
  let ops = main_body_ops(output.unwrap())
  assert_true(
    ops.exists(op => op is @opcode.OpCode::ShlQ),
    msg="1LL<<2u 期望 ShlQ（64 位左移）",
  )
  assert_false(
    ops.exists(op => op is @opcode.OpCode::Shl),
    msg="不应发射 32 位 Shl（LL 域不降级）",
  )
}

///|
/// P3-5：`LLONG_MAX + 1LL` → **AddQ**（I64 回绕格锚
/// `m08c_llong_max_plus1_wrap` 的发射面；i32 Add 的 trap 面已有既有锚，
/// Q 族回绕加的发射在此锁）。
test "parity_add_ll_emits_addq" {
  let ll = @ast.Type::long_long()
  let prog = minimal_program_with_return(
    @ast.Expr::Binary(
      @ast.BinaryOp::Add,
      @ast.Expr::LongLiteral(9223372036854775807L, loc(3), ll),
      @ast.Expr::LongLiteral(1L, loc(3), ll),
      loc(3),
      ll,
    ),
  )
  let gen = BytecodeGen::new()
  let (output, errors) = gen.generate(prog)
  assert_eq(errors.length(), 0)
  let ops = main_body_ops(output.unwrap())
  assert_true(
    ops.exists(op => op is @opcode.OpCode::AddQ),
    msg="LLONG_MAX+1LL 期望 AddQ（Q 族回绕，与 i32 trap 分口径）",
  )
  assert_false(
    ops.exists(op => op is @opcode.OpCode::Add),
    msg="不应发射 32 位 Add（LL 域不降级为 i32 trap 口径）",
  )
}

///|
/// P3-5：`(int)<double 常量>` → **CastD2I**（f2i 饱和锚
/// `m08c_f2i_saturate_1e300` 的发射面——1e10 与 1e300 同饱和格，锚定
/// opcode 族非具体值；本构造绕过 typeck 折叠直喂 codegen，Cast 臂真实发射）。
test "parity_cast_double_int_emits_castd2i" {
  let d = @ast.Type::double()
  let prog = minimal_program_with_return(
    @ast.Expr::Cast(
      @ast.Expr::FloatLiteral(10000000000.0, loc(3), d),
      @ast.Type::int(),
      loc(3),
      @ast.Type::int(),
    ),
  )
  let gen = BytecodeGen::new()
  let (output, errors) = gen.generate(prog)
  assert_eq(errors.length(), 0)
  let ops = main_body_ops(output.unwrap())
  assert_true(
    ops.exists(op => op is @opcode.OpCode::CastD2I),
    msg="(int)1e10 期望 CastD2I（f64→i32 饱和转换）",
  )
}
