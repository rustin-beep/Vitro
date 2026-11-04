///|
/// #425（审阅 v2 B2 批，2026-11-03）——判零截断族白盒锚。
///
/// 缺陷族（M13-A-1 / M13-A-4 / M12-A1）：
/// · &&/|| 操作数判零先发 CastF2I/CastD2I/CastQ2I（截断语义）——(0,1)
///   开区间浮点截断为 0 恒判假（`0.5f && 1` = 0）、低 32 位为零的 LL 判假；
/// · `!`（Not）不分派类型按 i32 位模式判——f32 位模式 0x80000000 非零
///   判真（`!(-0.0f)`=0）、LL 只看低 32 位（`!0x100000000LL`=1）；
/// · 复合赋值右操作数被预收口到左类型（typeck insert_implicit_cast）
///   ——`x /= 0.5` ≡ `x /= (int)0.5` = 假除零 trap 误杀合法程序。
///
/// 修复：①&&/|| 判零改数值比较（PushConstF/D/Q 0 + NeF/NeD/NeQ——栈上
/// 0/1 化，Dup/JumpIfZero 短路基态不变）；②Not 分派类型（浮点/LL 发
/// PushConst 0 + EqX——数值零判；int 家族位判照旧）；③复合赋值右值保
/// 原类型（typeck 不插收口 cast），运算域提升（左/右窄侧升到公共域）+
/// 运算后窄化回左类型由 codegen 发射（本文件第 3 锚锁指令序）。
/// 运行期真值由 corpus 三例（compound_fp_rhs / logic_judge_zero /
/// not_numeric_zero）经 clang_direct 直拍锁定。

///|
/// 辅助：函数体指令序里是否存在相邻 opcode 对。
/// #467 P3-2（2026-11-04 审阅处置）：扫描窗口限定**本函数体**——从 ip
/// 扫到首个 Ret/RetVoid（含）为止；旧形态扫到 code 末尾会跨进 wrapper/
/// 其他函数段（跨函数匹配假绿面）。
fn has_pair(
  code : Array[@opcode.Instruction],
  from : Int32,
  a : @opcode.OpCode,
  b : @opcode.OpCode,
) -> Bool {
  let end = code.length() - 1
  let mut i = from
  while i < end {
    if code[i].op == a && code[i + 1].op == b {
      return true
    }
    if code[i].op is Ret || code[i].op is RetVoid {
      break
    }
    i += 1
  }
  false
}

///|
/// 辅助：函数体指令序里是否出现某 opcode。
fn has_op(
  code : Array[@opcode.Instruction],
  from : Int32,
  a : @opcode.OpCode,
) -> Bool {
  let mut i = from
  while i < code.length() {
    if code[i].op == a {
      return true
    }
    if code[i].op is Ret || code[i].op is RetVoid {
      break
    }
    i += 1
  }
  false
}

///|
/// #425 F2（M13-A-1）：`d && 1`（d:double）——操作数判零须数值比较
/// （PushConstD 0 + NeD），禁截断 CastD2I（旧形态 (0,1) 浮点恒判假）。
test "judgezero: and/or operand numeric zero-test (#425 F2)" {
  let d_ty = @ast.Type::double()
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
              @ast.Stmt::VarDecl(d_ty, "d", None, [], false, false, loc(2)),
              @ast.Stmt::Expr(
                @ast.Expr::Binary(
                  @ast.BinaryOp::And,
                  @ast.Expr::Identifier("d", loc(2), d_ty),
                  @ast.Expr::Literal(1, loc(2), @ast.Type::int()),
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
  let ip = o.func_table.get("main").unwrap().ip
  let _ = ip
  assert_false(
    has_op(o.code, ip, @opcode.OpCode::CastD2I),
    msg="&& 操作数判零禁截断 CastD2I（(0,1) 浮点截断为 0 恒判假）",
  )
  assert_true(
    has_pair(o.code, ip, @opcode.OpCode::PushConstD, @opcode.OpCode::NeD),
    msg="double 操作数判零须数值比较 PushConstD 0 + NeD",
  )
}

///|
/// #425 F3（M13-A-4）：`!df`（df:double）与 `!q`（q:long long）——Not 须
/// 分派类型走数值零判（PushConst 0 + EqD/EqQ），禁裸 Not 位模式判。
test "judgezero: not per-type numeric zero (#425 F3)" {
  let d_ty = @ast.Type::double()
  let q_ty = @ast.Type::long_long()
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
              @ast.Stmt::VarDecl(d_ty, "df", None, [], false, false, loc(2)),
              @ast.Stmt::VarDecl(q_ty, "q", None, [], false, false, loc(2)),
              @ast.Stmt::Expr(
                @ast.Expr::Unary(
                  @ast.UnaryOp::Not,
                  @ast.Expr::Identifier("df", loc(2), d_ty),
                  loc(2),
                  @ast.Type::int(),
                ),
                loc(2),
              ),
              @ast.Stmt::Expr(
                @ast.Expr::Unary(
                  @ast.UnaryOp::Not,
                  @ast.Expr::Identifier("q", loc(3), q_ty),
                  loc(3),
                  @ast.Type::int(),
                ),
                loc(3),
              ),
              @ast.Stmt::Return(
                Some(@ast.Expr::Literal(0, loc(4), @ast.Type::int())),
                loc(4),
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
  let ip = o.func_table.get("main").unwrap().ip
  let _ = ip
  assert_false(
    has_op(o.code, ip, @opcode.OpCode::Not),
    msg="浮点/LL 的 ! 禁裸 Not（i32 位模式判——f32 位模式 0x80000000 判真/LL 只看低 32 位）",
  )
  assert_true(
    has_pair(o.code, ip, @opcode.OpCode::PushConstD, @opcode.OpCode::EqD),
    msg="!double 须数值零判 PushConstD 0 + EqD（!(-0.0) = 1）",
  )
  assert_true(
    has_pair(o.code, ip, @opcode.OpCode::PushConstQ, @opcode.OpCode::EqQ),
    msg="!LL 须数值零判 PushConstQ 0 + EqQ（!0x100000000LL = 0）",
  )
}

///|
/// #425 F1（M12-A1）：`x /= 0.5`（x:int）——复合赋值右值禁预收口
/// （C11 6.5.16.2p3：E1 op= E2 ≡ E1 = (T)(E1 op E2)，op 按常规算术
/// 转换）。旧形态 typeck 预插 (int)0.5 ⇒ 假除零 trap；新形态指令序=
/// LoadLocal x → CastI2D（左提升到运算域）→ PushConstD 0.5 → DivD
/// （运算域除）→ CastD2I（窄化回左类型）→ StoreLocal。
test "compound: fp rhs no pre-collapse (#425 F1)" {
  let x_ty = @ast.Type::int()
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
              @ast.Stmt::VarDecl(x_ty, "x", None, [], false, false, loc(2)),
              @ast.Stmt::Expr(
                @ast.Expr::Assign(
                  @ast.AssignOp::DivAssign,
                  @ast.Expr::Identifier("x", loc(2), x_ty),
                  @ast.Expr::FloatLiteral(0.5, loc(2), @ast.Type::double()),
                  loc(2),
                  x_ty,
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
  let ip = o.func_table.get("main").unwrap().ip
  assert_true(
    has_op(o.code, ip, @opcode.OpCode::DivD),
    msg="x /= 0.5 须 double 域除（旧形态右值预收口 (int)0.5=0 ⇒ int 域 Div 假除零 trap）",
  )
  assert_true(
    has_op(o.code, ip, @opcode.OpCode::CastI2D),
    msg="左操作数须提升到运算域 CastI2D",
  )
  assert_true(
    has_pair(o.code, ip, @opcode.OpCode::DivD, @opcode.OpCode::CastD2I),
    msg="运算后须窄化回左类型 DivD → CastD2I",
  )
}

///|
/// #425 连坐（M11-B1 挂空注释清偿）：`5 && 3` 结果规范化——T-P1-1 的
/// PushConst 0 + Ne 尾锚（此前注释挂空无锚，删 binary.mbt 两条指令
/// codegen 包全绿——本锚补突变防护）。
test "logical: 5&&3 normalization tail anchored (#425 / M11-B1)" {
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
                @ast.Expr::Binary(
                  @ast.BinaryOp::And,
                  @ast.Expr::Literal(5, loc(2), @ast.Type::int()),
                  @ast.Expr::Literal(3, loc(2), @ast.Type::int()),
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
  let ip = o.func_table.get("main").unwrap().ip
  assert_true(
    has_pair(o.code, ip, @opcode.OpCode::PushConst, @opcode.OpCode::Ne),
    msg="&& 结果须规范化 0/1（PushConst 0 + Ne 尾——T-P1-1；5&&3 得 1 非 3）",
  )
}

///|
/// #467 P1（2026-11-04 审阅处置）：复合赋值域提升的无符号轴——
/// `unsigned u; long long x; x += u` 左提升须 CastU2Q、`double d; d += u`
/// 须 CastU2D（跨符号位取值 u=4294967295 的正确性由语料
/// compound_unsigned_promote.c 直拍锁定；本锚锁指令族选型）。
test "compound: unsigned promote uses U-casts (#467 P1)" {
  let u_ty = @ast.Type::unsigned_int()
  fn mk(
    op : @ast.AssignOp,
    lty : @ast.Type,
    lname : String,
    rty : @ast.Type,
    rname : String,
  ) -> @ast.Stmt {
    @ast.Stmt::Expr(
      @ast.Expr::Assign(
        op,
        @ast.Expr::Identifier(lname, loc(2), lty),
        @ast.Expr::Identifier(rname, loc(2), rty),
        loc(2),
        lty,
      ),
      loc(2),
    )
  }
  let x_ty = @ast.Type::long_long()
  let d_ty = @ast.Type::double()
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
              @ast.Stmt::VarDecl(u_ty, "u", None, [], false, false, loc(2)),
              @ast.Stmt::VarDecl(x_ty, "x", None, [], false, false, loc(2)),
              @ast.Stmt::VarDecl(d_ty, "d", None, [], false, false, loc(2)),
              mk(@ast.AssignOp::AddAssign, x_ty, "x", u_ty, "u"),
              mk(@ast.AssignOp::AddAssign, d_ty, "d", u_ty, "u"),
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
  let ip = o.func_table.get("main").unwrap().ip
  assert_true(
    has_op(o.code, ip, @opcode.OpCode::CastU2Q),
    msg="x += u 的左提升须 CastU2Q（零扩展）——signed CastI2Q 在跨符号位取值下回绕成负数",
  )
  assert_true(
    has_op(o.code, ip, @opcode.OpCode::CastU2D),
    msg="d += u 的提升须 CastU2D（零扩展）——signed CastI2D 在跨符号位取值下得负浮点",
  )
  assert_false(
    has_op(o.code, ip, @opcode.OpCode::CastI2Q),
    msg="无符号源禁 signed CastI2Q（#467 P1 回归形态）",
  )
  // 注：CastI2D 全局禁断不成立——`double d;` 无初始化声明的零初始化路径
  // 合法发 PushConst 0 + CastI2D + StoreLocalD（与复合段无关）；复合段的
  // 选型由上方 CastU2D/CastU2Q 正断言锁定（LoadLocal 之后的提升）。
}
