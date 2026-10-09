///|
/// S3 parser 黑盒锚测试（J9 红→绿锚与搬运用例的起点批）。
/// 语料输入经 @lexer.tokenize（test-only import；包本身不依赖 lexer
/// 预处理实现——勘察 §9.2 依赖方向）。

///|
/// 便捷入口：源码 → ParseResult。
fn parse_src(src : String) -> @parser.ParseResult {
  let lexed = @lexer.tokenize(src)
  @parser.parse(lexed.tokens)
}

///|
/// 错误码序列。
fn codes_of(r : @parser.ParseResult) -> Array[Int] {
  let cs = []
  for e in r.errors {
    cs.push(e.code)
  }
  cs
}

///|
test "parse int main smoke" {
  let r = parse_src("int main() { return 0; }")
  assert_true(r.errors.is_empty())
  let p = r.program.unwrap()
  inspect(p.funcs.length(), content="1")
  inspect(p.funcs[0].name, content="main")
  inspect(p.funcs[0].params.length(), content="0")
}

///|
test "parse global and var decl" {
  let r = parse_src("int g = 1 + 2; int main() { int a = g; return a; }")
  assert_true(r.errors.is_empty())
  let p = r.program.unwrap()
  inspect(p.globals.length(), content="1")
  inspect(p.globals[0].name, content="g")
  inspect(p.funcs.length(), content="1")
}

///|
test "depth boundary paren 62 passes and 63 rejects" {
  // 勘察 A.1 实测口径：62 层通过 / 63 层 E1006（E1006 = 1006）
  let ok_src = "int main() { return " +
    "(".repeat(62) +
    "1" +
    ")".repeat(62) +
    "; }"
  let ok_r = parse_src(ok_src)
  inspect(codes_of(ok_r), content="[]")
  let bad_src = "int main() { return " +
    "(".repeat(63) +
    "1" +
    ")".repeat(63) +
    "; }"
  let bad_r = parse_src(bad_src)
  assert_true(bad_r.errors.length() > 0)
  inspect(bad_r.errors[0].code, content="1006")
  // 注意：Rust 语义下深度触发不返回 None——errors 非空但 program 仍可
  // 有占位 AST（上层见 errors 丢弃）；"是否 None"不是对拍面
}

///|
test "declarator suffix 1300 rejected cleanly" {
  // J1 不复刻验证：`int a[1]x1300` 必须诊断拒绝（Rust oracle 曾崩溃，
  // P1 修复后拒绝；MoonBit 侧绝不允许崩溃/挂死）
  let suffixes = "[1]".repeat(1300)
  let r = parse_src("int a\{suffixes};")
  assert_true(r.errors.length() > 0)
  inspect(r.errors[0].code, content="1006")
  // 同族：typedef / sizeof 抽象声明符 / 形参 / 结构体字段
  let r2 = parse_src("typedef int T\{suffixes};")
  assert_true(r2.errors.length() > 0)
  inspect(r2.errors[0].code, content="1006")
  let r3 = parse_src("int main() { return sizeof(int\{suffixes}); }")
  assert_true(r3.errors.length() > 0)
  inspect(r3.errors[0].code, content="1006")
  let r4 = parse_src("int f(int a\{suffixes}) { return 0; }")
  assert_true(r4.errors.length() > 0)
  let r5 = parse_src("struct S { int a\{suffixes}; };")
  assert_true(r5.errors.length() > 0)
}

///|
test "pointer chain 100 rejects" {
  // 指针链 100 个 `*` → E1007（勘察 6-4 通道）
  let stars = "*".repeat(100)
  let r = parse_src("int \{stars} p;")
  assert_true(r.errors.length() > 0)
  inspect(r.errors[0].code, content="1007")
}

///|
test "liveness stall count zero on garbage" {
  // 勘察 6-3 五种死循环形状：全部收敛 + stall_count = 0（活性三层约定
  // 兜底不触发——若触发即 stall_count > 0，防线上红）
  let shapes = [
    "struct S* ; int main() { return 0; }", "@#$%^", "int main() { int a = 1 @ ; }",
    "int main() { switch (0) { case 1: @ ; } return 0; }", "int main() { } } }",
  ]
  for src in shapes {
    let r = parse_src(src)
    inspect(r.stall_count, content="0")
    assert_true(r.errors.length() > 0)
  }
}

///|
test "typedef table drives is_type_token" {
  // Vitro oracle 语义：单 `long` 被限定符循环消费后 fallback——
  // `unsigned long` = unsigned int（long long 双写才是 64 位）
  let r = parse_src(
    "typedef unsigned long size_t_; size_t_ n; int main() { return 0; }",
  )
  assert_true(r.errors.is_empty())
  let p = r.program.unwrap()
  inspect(p.globals[0].name, content="n")
  match p.globals[0].ty {
    Int(true, _) => ()
    _ => fail("size_t_ 应解析为 unsigned int（单 long 语义）")
  }
  // long long 双写 → 64 位
  let r2 = parse_src(
    "typedef unsigned long long u64t; u64t n2; int main() { return 0; }",
  )
  assert_true(r2.errors.is_empty())
  let p2 = r2.program.unwrap()
  match p2.globals[0].ty {
    LongLong(true, _) => ()
    _ => fail("u64t 应解析为 unsigned long long")
  }
}

///|
test "unsigned literal value range dispatch" {
  // F-P0-2：4000000000 → LongLiteral 保真（i32 域外）
  let r = parse_src("int main() { return 4000000000; }")
  assert_true(r.errors.is_empty())
  let p = r.program.unwrap()
  match p.funcs[0].body {
    Some(Block(stmts, _)) =>
      match stmts[0] {
        Return(Some(LongLiteral(v, _, _)), _) =>
          inspect(v, content="4000000000")
        _ => fail("应为 LongLiteral")
      }
    _ => fail("应有函数体")
  }
}

///|
test "static assert true passes false fails" {
  let ok = parse_src("int main() { _Static_assert(1 == 1); return 0; }")
  inspect(codes_of(ok), content="[]")
  let bad = parse_src(
    "int main() { _Static_assert(1 == 2, \"mismatch\"); return 0; }",
  )
  inspect(bad.errors[0].code, content="1020")
}

///|
test "enum const evaluator checked semantics" {
  // U1#9：溢出/移位边界 → "非常量"诊断（E1006），不崩不错值
  let bad1 = parse_src("enum E { X = 1 << 1000 };")
  assert_true(bad1.errors.length() > 0)
  inspect(bad1.errors[0].code, content="1006")
  // 负数与四则折叠可用（F-P0-3）
  let ok = parse_src(
    "enum E { NEG = -1, BIG = 1 + 2 }; int main() { return 0; }",
  )
  inspect(codes_of(ok), content="[]")
  let p = ok.program.unwrap()
  inspect(p.globals.length(), content="2")
  match p.globals[0].init {
    Some(Literal(-1, _, _)) => ()
    _ => fail("NEG 应为 -1")
  }
}

///|
test "array param decays to pointer" {
  let r = parse_src("int f(int a[5]) { return a[0]; }")
  assert_true(r.errors.is_empty())
  let p = r.program.unwrap()
  match p.funcs[0].params[0].ty {
    Pointer(pointee, _) =>
      match pointee {
        Int(_, _) => () // int[5] → int*
        _ => fail("退化元素应为 int")
      }
    _ => fail("数组形参应退化为指针")
  }
}

///|
test "function pointer declarator spiral" {
  // int (*fp)(int, char) → Pointer(Function)
  let r = parse_src("int (*fp)(int, char);")
  assert_true(r.errors.is_empty())
  let p = r.program.unwrap()
  inspect(p.globals[0].name, content="fp")
  match p.globals[0].ty {
    Pointer(Function(_, params, _, _), _) =>
      inspect(params.length(), content="2")
    _ => fail("应为函数指针")
  }
}

///|
test "multi dim array dims merge" {
  let r = parse_src("int a[2][3];")
  assert_true(r.errors.is_empty())
  let p = r.program.unwrap()
  match p.globals[0].ty {
    Array(_, size, dims, _, _, _) => {
      inspect(size, content="6")
      inspect(dims.length(), content="2")
    }
    _ => fail("应为数组")
  }
}

///|
/// interpret 纯 Array 链迭代化的等价锚：dims 顺序（外→内）与 Rust 递归
/// 合并序一致（最内维先成，外层逐层 push）。
test "array chain dims order" {
  // Rust 真值仲裁（serve ast.dump）：dims = [2,3,4] 源码序——声明符
  // 后缀从内向外包（[2] 最先、[4] 最外），interpret 从外层解起逐层
  // push → 源码序
  let r = parse_src("int a[2][3][4];")
  let p = r.program.unwrap()
  match p.globals[0].ty {
    Array(_, size, dims, _, _, _) => {
      inspect(size, content="24")
      inspect(dims[0], content="2")
      inspect(dims[1], content="3")
      inspect(dims[2], content="4")
    }
    _ => fail("应为三维数组")
  }
}

///|
/// VLA 维度传播（迭代折叠保留 is_vla/vla_dims 链）。
test "vla propagation through chain" {
  let r = parse_src("int main() { int n = 3; int a[n][4]; return 0; }")
  let p = r.program.unwrap()
  match p.funcs[0].body {
    Some(Block(stmts, _)) =>
      match stmts[1] {
        VarDecl(ty, _, _, _, _, _) =>
          match ty {
            Array(_, _, dims, _, is_vla, vla_dims) => {
              inspect(is_vla, content="true")
              inspect(dims.length(), content="2")
              inspect(vla_dims.length(), content="1")
            }
            _ => fail("应为 VLA 数组")
          }
        _ => fail("第二句应为声明")
      }
    _ => fail("应有函数体")
  }
}

///|
/// 复合字面量 + 匿名 struct 回滚（U1#10 场景：试探失败不二次 push 匿名
/// struct——全量快照面）。
test "compound literal anonymous struct" {
  let r = parse_src("int main() { return (struct { int a; }) { 7 } . a; }")
  assert_true(r.errors.is_empty())
  let p = r.program.unwrap()
  // 匿名 struct 进入 structs（parse() 尾部 append）
  inspect(p.structs.length() >= 1, content="true")
  // 无重复定义诊断
  for e in r.errors {
    inspect(e.code != 3002, content="true")
  }
}

///|
test "b3a_parser_five_fixes" {
  // 批三-a 五销案锚（2026-10-06，issue #4/#7/#11/#12/#15）
  // #4：初始化列表尾逗号（C89/C11 合法）
  let r1 = @parser.parse(@lexer.tokenize("int a[3] = {1, 2, };").tokens)
  assert_eq(r1.errors.length(), 0, msg="#4 尾逗号")
  // #7：匿名 union 内联 body（parse 层零错）
  let r2 = @parser.parse(
    @lexer.tokenize(
      "struct S { int pre; union { int a; float b; }; int post; };",
    ).tokens,
  )
  assert_eq(r2.errors.length(), 0, msg="#7 匿名 union 内联")
  // #11：bool 不再注册 C 关键字（_Bool 保留；typedef int bool; 合法）
  let r3 = @parser.parse(@lexer.tokenize("typedef int bool;").tokens)
  assert_eq(r3.errors.length(), 0, msg="#11 bool 让位 typedef")
  // #12：未定义类型名 `A B;` 报「未定义的标识符」非「预期 ';'」
  let r4 = @parser.parse(
    @lexer.tokenize("int main() { fpos_t pos; return 0; }").tokens,
  )
  assert_eq(r4.errors.length(), 1, msg="#12 单错")
  assert_true(
    r4.errors[0].message.contains("未定义的标识符"),
    msg="#12 文案直指真因",
  )
  // #15：匿名 enum 两形状（顶层带声明器 + struct 成员）
  let r5 = @parser.parse(@lexer.tokenize("enum { A, B } pair;").tokens)
  assert_eq(r5.errors.length(), 0, msg="#15 顶层 enum 声明器")
  let r6 = @parser.parse(
    @lexer.tokenize("struct T { enum { X, Y } k; int v; };").tokens,
  )
  assert_eq(r6.errors.length(), 0, msg="#15 成员 enum")
}

///|
test "b3b_static_assert_sizeof_aggregate" {
  // issue #13 销案锚（2026-10-06）：static_assert 条件的 sizeof 聚合/
  // 数组折叠（parsed_aggregates/parsed_var_types 声明点收口表）+ 顶层
  // _Static_assert 组合形态（trailing_globals 曾吞成函数声明器）
  let src = "struct P { int a; int b; };\nunion U { int a; double d; };\nint g[6];\n_Static_assert(sizeof(struct P) == 8, \"s\");\n_Static_assert(sizeof(union U) == 8, \"u\");\n_Static_assert(sizeof(g) == 24, \"g\");\nint main() { int arr[4]; _Static_assert(sizeof(arr) == 16, \"a\"); return 0; }"
  let r = @parser.parse(@lexer.tokenize(src).tokens)
  assert_eq(r.errors.length(), 0, msg="五断言全过零错")
  // 反锚：断言失败必须报 E1020
  let r2 = @parser.parse(
    @lexer.tokenize(
      "struct P { int a; };\n_Static_assert(sizeof(struct P) == 99, \"fail\");",
    ).tokens,
  )
  assert_eq(r2.errors.length(), 1)
  assert_true(r2.errors[0].code == 1020, msg="失败断言报 E1020")
}

///|
test "b3rv_scope_barrier_var_types" {
  // 审阅 P1-1 锚（2026-10-07）：block 内声明的 sizeof 折叠语义不出块
  //（内层 double x 污染外层 int x 的折叠——旧单表 append-only 形态）
  let src = "int main() {\n    int x = 1;\n    { double x = 2.0; }\n    _Static_assert(sizeof(x) == 4, \"outer\");\n    return x;\n}"
  let r = @parser.parse(@lexer.tokenize(src).tokens)
  assert_eq(r.errors.length(), 0, msg="外层 int 不被内层 double 污染")
  let src2 = "int main() {\n    double x = 1.5;\n    _Static_assert(sizeof(x) == 8, \"d\");\n    return 0;\n}"
  let r2 = @parser.parse(@lexer.tokenize(src2).tokens)
  assert_eq(r2.errors.length(), 0, msg="无遮蔽正向仍过")
  let src3 = "int main() {\n    int x = 1;\n    { double x = 2.0; _Static_assert(sizeof(x) == 8, \"inner\"); }\n    return x;\n}"
  let r3 = @parser.parse(@lexer.tokenize(src3).tokens)
  assert_eq(r3.errors.length(), 0, msg="内层自身可见")
}

///|
/// issue #48 红→绿主锚：顶层声明缺 ';' 且 '{' 紧随（学生漏写参数括号）
/// ——Clang 式 panic-mode 恢复后级联归零，只留病根 1 条（修前 8 条）。
test "parse decl missing semi with brace collapses to root" {
  let r = parse_src("int main{\n int a,b;\n printf(\"hello\");\n};\n")
  inspect(r.errors.length(), content="1")
  inspect(r.errors[0].code, content="2005")
  inspect(r.errors[0].line, content="1")
  inspect(r.errors[0].column, content="5")
}

///|
/// issue #48 垃圾 token 变体：首错行内丢弃语义（dadadas 恒零诊断），
/// 整块吞到配平 '}' + 尾 ';'——与不带 dadadas 版逐条相同。
test "parse decl brace junk swallow keeps root only" {
  let r = parse_src("int main{dadadas\n int a,b;\n printf(\"hello\");\n};\n")
  inspect(r.errors.length(), content="1")
  inspect(r.errors[0].code, content="2005")
}

///|
/// issue #48 防吞过头：块 + 尾 ';' 消费后下一声明正常入列。
test "parse decl brace recovery keeps next decl" {
  let r = parse_src("int a{3}; int b;\n")
  inspect(r.errors.length(), content="1")
  let p = r.program.unwrap()
  assert_true(p.globals.length() >= 1, msg="int b; 须正常入列")
  assert_eq(p.globals[p.globals.length() - 1].name, "b", msg="末位全局 = b")
}

///|
/// issue #48 形状锁定：缺 ';' 但**无** '{' 紧随的旧恢复路径零扰动
///（synchronize 停 ';' 前 → 顶层报 UnexpectedTop 一条——历史形状，锁 2 条）。
test "parse decl missing semi without brace keeps legacy shape" {
  let r = parse_src("int x y;\n")
  inspect(r.errors.length(), content="2")
  inspect(r.errors[0].code, content="2005")
  inspect(r.errors[1].code, content="2005")
}
