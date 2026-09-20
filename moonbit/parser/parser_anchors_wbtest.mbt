///|
/// S3 白盒锚（形态改造面的单点验证——黑盒对拍之外的构造性证据）：
/// 1. 深度参数语义：壳挂点的计数口径与 Rust 共享计数器同构
/// 2. 回滚全量快照：A5 第 4 类缺口的结构性消除
///（wbtest 不携带 lexer 依赖——token 数组手工构造）

///|
/// 手工 token（裸最小面）。
fn tok(
  ty : @token.TokenType,
  text : String,
  line : Int,
  col : Int,
) -> @token.Token {
  {
    ty,
    text,
    loc: { line, column: col, file_id: 0, },
    byte_off: -1,
    real_line: -1,
  }
}

///|
fn num_tokens(n : Int) -> Array[@token.Token] {
  let toks = []
  for i in 0..<n {
    toks.push(tok(Number, i.to_string(), 1, 1 + i * 2))
  }
  toks.push(tok(Eof, "", 1, 1 + n * 2))
  toks
}

///|
/// 深度壳检查边界：depth = MAX 时立即拒绝并跳尾（Rust enter_depth 同构）。
test "wb depth shell rejects at max" {
  let q = Parser::with_mode(num_tokens(4), false)
  let before = q.errors.length()
  ignore(q.parse_assign(MAX_PARSE_DEPTH))
  inspect(q.errors.length() - before, content="1")
  inspect(q.errors[before].code, content="1006")
  // 跳尾副作用：pos = len-1
  inspect(q.pos, content="4")
}

///|
/// depth = MAX-1 通过检查，body 内下一层壳（收 MAX）拒绝。
test "wb depth shell boundary off by one" {
  let q = Parser::with_mode(num_tokens(4), false)
  ignore(q.parse_assign(MAX_PARSE_DEPTH - 1))
  assert_true(q.errors.length() > 0)
  inspect(q.errors[0].code, content="1006")
}

///|
/// 回滚快照含 typedef_names（A5 结构性消除验证）。
test "wb rollback covers typedef table" {
  let q = Parser::with_mode(num_tokens(1), false)
  let rb = q.save()
  q.typedef_names.set("ProbeT", @ast.Type::int())
  inspect(q.typedef_names.contains("ProbeT"), content="true")
  q.restore(rb)
  inspect(q.typedef_names.contains("ProbeT"), content="false")
}

///|
/// 回滚快照含 current_class / next_lambda_id / errors / anonymous_structs。
test "wb rollback covers class stack and lambda id" {
  let q = Parser::with_mode(num_tokens(1), false)
  let rb = q.save()
  q.current_class.push("Outer")
  q.next_lambda_id = 7
  q.errors.push({ message: "x", line: 1, column: 1, code: 1, })
  q.anonymous_structs.push({
    loc: @source.SourceLoc::new(1, 1),
    name: "S",
    fields: [],
  })
  q.restore(rb)
  inspect(q.current_class.length(), content="0")
  inspect(q.next_lambda_id, content="0")
  inspect(q.errors.length(), content="0")
  inspect(q.anonymous_structs.length(), content="0")
}

///|
/// FILE 预定义登记（Rust with_mode 同款）。
test "wb predefined FILE typedef" {
  let q = Parser::with_mode(num_tokens(1), false)
  inspect(q.typedef_names.contains("FILE"), content="true")
}

///|
/// F2 锚：eval_enum_const 显式栈迭代——1200 项左链深表达式在递归版
/// 栈溢出（修复前红），迭代版返回正确值（修复后绿）。
test "wb eval_enum_const deep chain iterative" {
  let one : @ast.Expr = @ast.Expr::Literal(
    1,
    @source.SourceLoc::new(1, 1),
    @ast.Type::int(),
  )
  let mut e = one
  for i in 0..<1200 {
    e = @ast.Expr::Binary(
      @ast.BinaryOp::Add,
      e,
      @ast.Expr::Literal(
        1,
        @source.SourceLoc::new(1, 1 + i * 2),
        @ast.Type::int(),
      ),
      @source.SourceLoc::new(1, 1 + i * 2),
      @ast.Type::int(),
    )
  }
  match eval_enum_const(e) {
    Some(v) => inspect(v, content="1201")
    None => fail("1200 项常量链应可求值")
  }
}

///|
/// F2 锚：迭代化行为等价抽查（负/取反/移位/除零与递归版语义一致——
/// checked None 走"非常量表达式"）。
test "wb eval_enum_const semantics spot checks" {
  let loc = @source.SourceLoc::new(1, 1)
  let ty = @ast.Type::int()
  let lit = fn(v : Int) -> @ast.Expr { @ast.Expr::Literal(v, loc, ty) }
  // 2 + 3 * 4 = 14
  let e1 = @ast.Expr::Binary(
    @ast.BinaryOp::Add,
    lit(2),
    @ast.Expr::Binary(@ast.BinaryOp::Mul, lit(3), lit(4), loc, ty),
    loc,
    ty,
  )
  match eval_enum_const(e1) {
    Some(v) => inspect(v, content="14")
    None => fail("2+3*4 应可求值")
  }
  // 1 << 100 移位量非法 → None
  let e2 = @ast.Expr::Binary(@ast.BinaryOp::Shl, lit(1), lit(100), loc, ty)
  match eval_enum_const(e2) {
    Some(_) => fail("移位量 ≥64 应 None")
    None => ()
  }
  // 1 / 0 → None（除零显式零检查）
  let e3 = @ast.Expr::Binary(@ast.BinaryOp::Div, lit(1), lit(0), loc, ty)
  match eval_enum_const(e3) {
    Some(_) => fail("除零应 None")
    None => ()
  }
}

///|
/// F3 锚：声明符 Array 链尾为 Pointer 的 C 语义折叠——
/// Array[3](Array[2](Pointer(Base))) 应产出 Pointer(Array{dims:[2,3]})
/// （裁定 b；修复前为撕裂的 Array{dims:[2,3], element:Pointer(Int)}）。
test "wb interpret arrptr multidim c semantics" {
  let q = Parser::with_mode(num_tokens(1), false)
  let size2 : @ast.Expr? = Some(
    @ast.Expr::Literal(2, @source.SourceLoc::new(1, 1), @ast.Type::int()),
  )
  let size3 : @ast.Expr? = Some(
    @ast.Expr::Literal(3, @source.SourceLoc::new(1, 1), @ast.Type::int()),
  )
  let node = Array(Array(Pointer(Base), size2), size3)
  match q.interpret_declarator_node(node, @ast.Type::int(), 0) {
    @ast.Type::Pointer(pointee, _) =>
      match pointee {
        @ast.Type::Array(_, sz, dims, _, _, _) => {
          inspect(dims, content="[2, 3]")
          inspect(sz, content="6")
        }
        _ => fail("pointee 应为数组")
      }
    _ => fail("应为指针在最外层")
  }
}

///|
/// F3 对照锚：尾为 Base 的纯数组链折叠不变（dims 合并序与改造前一致）。
test "wb interpret pure array chain unchanged" {
  let q = Parser::with_mode(num_tokens(1), false)
  let mk = fn(v : Int) -> @ast.Expr? {
    Some(@ast.Expr::Literal(v, @source.SourceLoc::new(1, 1), @ast.Type::int()))
  }
  let node = Array(Array(Array(Base, mk(2)), mk(3)), mk(4))
  match q.interpret_declarator_node(node, @ast.Type::int(), 0) {
    @ast.Type::Array(_, sz, dims, _, _, _) => {
      inspect(dims, content="[2, 3, 4]")
      inspect(sz, content="24")
    }
    _ => fail("纯数组链应折叠为数组")
  }
}

///|
/// G1 锚：零推进熔断——stall_count 超限后 stall_breaker 出 E1006 诊断
/// 并强推一个 token（真死循环可观测、终止性有下界）。
test "wb stall breaker forces progress beyond limit" {
  let q = Parser::with_mode(num_tokens(4), false)
  q.stall_count = MAX_STALL_ROUNDS + 1
  let before_errors = q.errors.length()
  let before_pos = q.pos
  inspect(q.stall_breaker(), content="true")
  inspect(q.errors.length() - before_errors, content="1")
  inspect(q.errors[before_errors].code, content="1006")
  inspect(q.pos - before_pos, content="1")
  // 未超限时不干预
  let q2 = Parser::with_mode(num_tokens(4), false)
  q2.stall_count = MAX_STALL_ROUNDS
  inspect(q2.stall_breaker(), content="false")
}

///|
/// F3-v2 锚（累加器一次收口）：括号内含数组 + 外层多维——
/// `int (*p[2])[3][4]` 应为 Array{[2], Pointer(Array{[3,4]})}
/// （Clang `int (*[2])[3][4]`；此前补丁产出 Pointer(Array{[2,3,4]})）。
test "wb interpret inner array dims c semantics" {
  let q = Parser::with_mode(num_tokens(1), false)
  let mk = fn(v : Int) -> @ast.Expr? {
    Some(@ast.Expr::Literal(v, @source.SourceLoc::new(1, 1), @ast.Type::int()))
  }
  // (*p[2])[3][4] 的链：括号内 *p[2] → Pointer(Array(Base,2))（前缀最后
  // 包最外）；括号外 [3][4] 逐层包 → Array(Array(Pointer(Array(Base,2)),3),4)
  let node = Array(Array(Pointer(Array(Base, mk(2))), mk(3)), mk(4))
  match q.interpret_declarator_node(node, @ast.Type::int(), 0) {
    @ast.Type::Array(_, sz, dims, _, _, _) => {
      inspect(dims, content="[2]")
      inspect(sz, content="2")
      match q.interpret_declarator_node(node, @ast.Type::int(), 0) {
        @ast.Type::Array(elem, _, _, _, _, _) =>
          match elem {
            @ast.Type::Pointer(pointee, _) =>
              match pointee {
                @ast.Type::Array(_, psz, pdims, _, _, _) => {
                  inspect(pdims, content="[3, 4]")
                  inspect(psz, content="12")
                }
                _ => fail("pointee 应为数组")
              }
            _ => fail("元素应为指针")
          }
        _ => fail("不可达")
      }
    }
    other => {
      ignore(other)
      fail("外层应为 Array(dims=[2])")
    }
  }
}

///|
/// F3-v2 锚：函数返回"指向数组的指针"——`int (*f(void))[2][3]` 的
/// 声明符值为 Pointer(Function(ret=Pointer(Array{[2,3]})))
/// （Vitro 函数 decay 约定：Function 值语义 = 函数指针，吸收内层 `*`）。
test "wb interpret fnret arrptr c semantics" {
  let q = Parser::with_mode(num_tokens(1), false)
  let mk = fn(v : Int) -> @ast.Expr? {
    Some(@ast.Expr::Literal(v, @source.SourceLoc::new(1, 1), @ast.Type::int()))
  }
  // (*f(void))[2][3] 的链：Array(Array(Pointer(Function(Base,[])),2),3)
  let node = Array(Array(Pointer(Function(Base, [], false)), mk(2)), mk(3))
  match q.interpret_declarator_node(node, @ast.Type::int(), 0) {
    @ast.Type::Pointer(pointee, _) =>
      match pointee {
        @ast.Type::Function(ret, _, _, _) =>
          match ret {
            @ast.Type::Pointer(p2, _) =>
              match p2 {
                @ast.Type::Array(_, sz, dims, _, _, _) => {
                  inspect(dims, content="[2, 3]")
                  inspect(sz, content="6")
                }
                _ => fail("返回类型应指向数组")
              }
            _ => fail("返回类型应是指针")
          }
        _ => fail("pointee 应为函数")
      }
    _ => fail("外层应为函数指针（decay）")
  }
}

///|
/// F3-v2 守卫锚：函数指针形态在累加器下与原表示一致——
/// `(*fp)(void)` → Pointer(Function)，`(*fp[2])(void)` → Array{[2],
/// Pointer(Function)}（decay 吸收内层 `*`，不双包）。
test "wb interpret fnptr decay guard" {
  let q = Parser::with_mode(num_tokens(1), false)
  // (*fp)(void) 链：Function(Pointer(Base), [])
  match
    q.interpret_declarator_node(
      Function(Pointer(Base), [], false),
      @ast.Type::int(),
      0,
    ) {
    @ast.Type::Pointer(pointee, _) =>
      match pointee {
        @ast.Type::Function(_, _, _, _) => ()
        _ => fail("应为单层 Pointer(Function)")
      }
    _ => fail("应为函数指针")
  }
  // (*fp[2])(void) 链：括号内 *fp[2] → Pointer(Array(Base,2))；括号外
  // 函数后缀 → Function(Pointer(Array(Base,2)), [])
  let mk = fn(v : Int) -> @ast.Expr? {
    Some(@ast.Expr::Literal(v, @source.SourceLoc::new(1, 1), @ast.Type::int()))
  }
  match
    q.interpret_declarator_node(
      Function(Pointer(Array(Base, mk(2))), [], false),
      @ast.Type::int(),
      0,
    ) {
    @ast.Type::Array(elem, _, dims, _, _, _) => {
      inspect(dims, content="[2]")
      match elem {
        @ast.Type::Pointer(_, _) => ()
        _ => fail("元素应为函数指针")
      }
    }
    _ => fail("应为函数指针数组")
  }
}
