///|
/// promote_type rank 表锚（C usual arithmetic conversions——Rust
/// `promote_type` 同构；改 rank 或 unsigned 传播规则此锚红）。
test "promote_type_rank_table" {
  let int = @ast.Type::int()
  let char_ = @ast.Type::char()
  let double = @ast.Type::double()
  let float = @ast.Type::float()
  let ll = @ast.Type::long_long()
  assert_true(promote_type(int, char_) is Int(_, _)) // char 提升 int
  assert_true(promote_type(char_, int) is Int(_, _))
  assert_true(promote_type(int, double) is Double(_))
  assert_true(promote_type(float, double) is Double(_))
  assert_true(promote_type(int, float) is Float(_))
  assert_true(promote_type(ll, int) is LongLong(_, _))
  assert_true(promote_type(char_, char_) is Int(_, _))
  // unsigned 传播（higher 或 lower 任一 unsigned）
  assert_true(promote_type(@ast.Type::unsigned_int(), int) is Int(true, _))
  assert_true(promote_type(int, @ast.Type::unsigned_int()) is Int(true, _))
}

///|
/// Offsetof 前置 lowering（struct 偏移累计 → Literal；union 恒 0；
/// 未知字段/未知类型诊断）。依赖 structs 符号表（Pass 1 已注册形态）。
test "resolve_expr_offsetof_lowering" {
  let loc = @source.SourceLoc::new(2, 10)
  let tc = TypeChecker::new()
  tc.enter_scope()
  // 手工注册 struct S { char a; int b; char c; }（packed 布局下 1+4+1）
  tc.structs.set("S", {
    fields: [(@ast.Type::char(), "a"), (int2(), "b"), (@ast.Type::char(), "c")],
  })
  // offsetof(S, c) = sizeof(char) + sizeof(int) + 0 = 5
  let (_, e) = tc.resolve_expr_type(
    @ast.Expr::Offsetof(@ast.Type::struct_type("S"), "c", loc, @ast.Type::int()),
  )
  match e {
    Literal(v, _, ty) => {
      assert_eq(v, 5)
      assert_true(ty is Int(_, _))
    }
    _ => fail("offsetof 应 lowering 为 Literal")
  }
  assert_eq(tc.errors.length(), 0)
  // union 恒 0
  tc.unions.set("U", { fields: [(int2(), "x"), (@ast.Type::char(), "y")], })
  let (_, e2) = tc.resolve_expr_type(
    @ast.Expr::Offsetof(@ast.Type::union_type("U"), "y", loc, @ast.Type::int()),
  )
  match e2 {
    Literal(v, _, _) => assert_eq(v, 0)
    _ => fail("union offsetof 应为 0")
  }
  // 未知字段 E3042
  let _ = tc.resolve_expr_type(
    @ast.Expr::Offsetof(
      @ast.Type::struct_type("S"),
      "zzz",
      loc,
      @ast.Type::int(),
    ),
  )
  assert_eq(tc.errors.length(), 1)
  assert_true(tc.errors[0].code == 3042)
}

///|
fn int2() -> @ast.Type {
  @ast.Type::int()
}

///|
/// identifier 定型三面（变量查表 + ty 写入重建节点 / 函数名→函数指针 /
/// 未声明 E3023 + int 兜底）。
test "resolve_identifier_shapes" {
  let loc = @source.SourceLoc::new(3, 5)
  let tc = TypeChecker::new()
  tc.enter_scope()
  tc.declare_var("x", int2(), is_global=false, is_extern=false, is_static=false)
  tc.funcs.set("f", {
    return_type: @ast.Type::double(),
    param_types: [int2()],
    is_variadic: false,
    param_defaults: [],
  })
  // 变量：ty 写入重建节点
  let (ty, e) = tc.resolve_expr_type(
    @ast.Expr::Identifier("x", loc, @ast.Type::void_type()),
  )
  assert_true(ty is Int(_, _))
  match e {
    @ast.Expr::Identifier(n, _, t) => {
      assert_eq(n, "x")
      assert_true(t is Int(_, _))
    }
    _ => fail("identifier 重建形态")
  }
  // 函数名作值：函数指针定型
  let (fty, _) = tc.resolve_expr_type(
    @ast.Expr::Identifier("f", loc, @ast.Type::void_type()),
  )
  match fty {
    Pointer(pointee, _) =>
      match pointee {
        Function(ret, params, _, _) => {
          assert_true(ret is Double(_))
          assert_eq(params.length(), 1)
        }
        _ => fail("函数指针 pointee 形态")
      }
    _ => fail("函数名应定型为函数指针")
  }
  // 未声明：E3023 + int 兜底
  let (uty, _) = tc.resolve_expr_type(
    @ast.Expr::Identifier("nope", loc, @ast.Type::void_type()),
  )
  assert_true(uty is Int(_, _))
  assert_eq(tc.errors.length(), 1)
  assert_true(tc.errors[0].code == 3023)
}

///|
/// string 字面量字节长度（P4 Latin-1 通道：\xHH ≥ 0x80 单字节、
/// 多字节源字符按 UTF-8；+1 结尾 NUL）。
test "string_literal_byte_len" {
  assert_eq(c_string_len("hi"), 2)
  assert_eq(c_string_len(""), 0)
  // \xff（码点 0xFF）单字节（Latin-1 通道——与 Rust cstring_len 同源）
  assert_eq(c_string_len("\u00ff"), 1)
  // 中文（码点 > 0xFF）按 UTF-8 三字节
  assert_eq(c_string_len("中"), 3)
  // 定型：char 数组 dims=[len+1]
  let tc = TypeChecker::new()
  let (ty, e) = tc.resolve_expr_type(
    @ast.Expr::StringLiteral(
      "hi",
      @source.SourceLoc::new(1, 1),
      @ast.Type::void_type(),
    ),
  )
  match ty {
    Array(elem, size, dims, _, _, _) => {
      assert_true(elem is Char(_, _))
      assert_eq(size, 3)
      assert_eq(dims.length(), 1)
      assert_eq(dims[0], 3)
    }
    _ => fail("string 应定型 char 数组")
  }
  match e {
    @ast.Expr::StringLiteral(_, _, t) =>
      assert_true(t is Array(_, _, _, _, _, _))
    _ => fail("string 重建形态")
  }
}

///|
/// index 定型（数组→subscript / 指针→pointee / 非 int 索引 E3039 /
/// 非数组指针 E3040）。
test "resolve_index_shapes" {
  let loc = @source.SourceLoc::new(1, 8)
  let tc = TypeChecker::new()
  tc.enter_scope()
  tc.declare_var(
    "arr",
    @ast.Type::array_of(int2(), [2, 3]),
    is_global=false,
    is_extern=false,
    is_static=false,
  )
  tc.declare_var(
    "p",
    @ast.Type::pointer_to(@ast.Type::double()),
    is_global=false,
    is_extern=false,
    is_static=false,
  )
  let idx = @ast.Expr::Literal(1, loc, int2())
  let ident : (String) -> @ast.Expr = fn(n) {
    @ast.Expr::Identifier(n, loc, @ast.Type::void_type())
  }
  // 数组：subscript（int[2][3] 索一次 → int[3]）
  let (ty1, _) = tc.resolve_expr_type(
    @ast.Expr::Index(ident("arr"), idx, loc, @ast.Type::void_type()),
  )
  match ty1 {
    Array(_, _, dims, _, _, _) => {
      assert_eq(dims.length(), 1)
      assert_eq(dims[0], 3)
    }
    _ => fail("数组 index 应 subscript")
  }
  // 指针：pointee（double* 索一次 → double）
  let (ty2, _) = tc.resolve_expr_type(
    @ast.Expr::Index(ident("p"), idx, loc, @ast.Type::void_type()),
  )
  assert_true(ty2 is Double(_))
  // 非 int 索引：E3039
  let _ = tc.resolve_expr_type(
    @ast.Expr::Index(
      ident("arr"),
      @ast.Expr::FloatLiteral(1.5, loc, @ast.Type::float()),
      loc,
      @ast.Type::void_type(),
    ),
  )
  assert_eq(tc.errors.length(), 1)
  assert_true(tc.errors[0].code == 3039)
  // 非数组/指针：E3040
  tc.declare_var("n", int2(), is_global=false, is_extern=false, is_static=false)
  let _ = tc.resolve_expr_type(
    @ast.Expr::Index(ident("n"), idx, loc, @ast.Type::void_type()),
  )
  assert_eq(tc.errors.length(), 2)
  assert_true(tc.errors[1].code == 3040)
}
