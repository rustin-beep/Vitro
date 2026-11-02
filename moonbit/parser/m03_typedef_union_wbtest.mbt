///|
/// M03-A2/A1 回归锚（审阅 v2 批 B9 第二批，2026-11-02，#433）：
/// typedef union TAG{...} 别名 与 嵌套/局部 union 的 is_union 记表。
/// 修前：typedef union 落 TypedefPlain → Union 臂丢 tag 不解析 body
/// ⇒ E2005×3+E3042×2 炸穿；parsed_aggregates 记 struct ⇒ snapshot
/// unions 表查无 ⇒ _Static_assert(sizeof) E1006 假阳性。红形态证据 =
/// 审阅现场 probes p2a/p1b/p1c/p1g/p1h CLI 跑红实录（本批 commit）。

///|
fn tok03(
  ty : @token.TokenType,
  text : String,
  line : Int32,
  col : Int32,
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
/// `typedef union VV { int a; double b; } VV;` 全形态——parse 后 unions
/// 表收具名条目 + 别名按 union_type 注册。
test "m03_typedef_union_tag_body_parses" {
  let toks = [
    tok03(Typedef, "typedef", 1, 1),
    tok03(Union, "union", 1, 9),
    tok03(Identifier, "VV", 1, 15),
    tok03(LBrace, "{", 1, 18),
    tok03(Int, "int", 2, 3),
    tok03(Identifier, "a", 2, 7),
    tok03(Semicolon, ";", 2, 8),
    tok03(Double, "double", 3, 3),
    tok03(Identifier, "b", 3, 10),
    tok03(Semicolon, ";", 3, 11),
    tok03(RBrace, "}", 4, 1),
    tok03(Identifier, "VV", 4, 3),
    tok03(Semicolon, ";", 4, 5),
    tok03(Eof, "", 4, 6),
  ]
  let p = Parser::with_mode(toks, false)
  let program : @ast.ProgramNode = {
    structs: [],
    unions: [],
    globals: [],
    funcs: [],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
  let kind = p.classify_top_level()
  let got_struct_decl = kind is TypedefStructDecl
  assert_true(
    got_struct_decl,
    msg="typedef union [名] { 应判 TypedefStructDecl（M03-A2 前瞻）",
  )
  p.dispatch_top_level(program, kind)
  assert_eq(
    program.unions.length(),
    1,
    msg="union body 应收进 program.unions（union 布局语义通道）",
  )
  match program.unions.get(0) {
    Some(d) =>
      assert_eq(
        d.name,
        "VV",
        msg="tag 名不得丢弃（旧 union_type(\"\") 炸穿形态）",
      )
    None => fail("unions 表空")
  }
  match p.typedef_names.get("VV") {
    Some(t) =>
      assert_true(
        t.kind() is TK_Union,
        msg="别名 VV 应按 union_type 注册（旧落 struct/空名形态）",
      )
    None => fail("typedef VV 未注册")
  }
}

///|
/// 对照：typedef struct 路径在 is_union 泛化后不回归（病 65 多声明器形态）。
test "m03_typedef_struct_regression" {
  let toks = [
    tok03(Typedef, "typedef", 1, 1),
    tok03(Struct, "struct", 1, 9),
    tok03(Identifier, "NN", 1, 16),
    tok03(LBrace, "{", 1, 19),
    tok03(Int, "int", 2, 3),
    tok03(Identifier, "a", 2, 7),
    tok03(Semicolon, ";", 2, 8),
    tok03(RBrace, "}", 3, 1),
    tok03(Identifier, "NN", 3, 3),
    tok03(Semicolon, ";", 3, 5),
    tok03(Eof, "", 3, 6),
  ]
  let p = Parser::with_mode(toks, false)
  let program : @ast.ProgramNode = {
    structs: [],
    unions: [],
    globals: [],
    funcs: [],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
  p.dispatch_top_level(program, p.classify_top_level())
  assert_eq(
    program.structs.length(),
    1,
    msg="struct 路径不受 is_union 泛化影响",
  )
  assert_eq(program.unions.length(), 0, msg="struct 不得串灌 unions 表")
}

///|
/// M03-A1：struct 成员位嵌套 union 的 is_union 记表位（parsed_aggregates
/// 第二元 = true——snapshot_unions_table 只收该位条目， folding 通道依赖）。
test "m03_nested_union_recorded_as_union" {
  let toks = [
    tok03(Struct, "struct", 1, 1),
    tok03(Identifier, "S", 1, 8),
    tok03(LBrace, "{", 1, 10),
    tok03(Union, "union", 2, 3),
    tok03(LBrace, "{", 2, 9),
    tok03(Int, "int", 2, 11),
    tok03(Identifier, "a", 2, 15),
    tok03(Semicolon, ";", 2, 16),
    tok03(Double, "double", 2, 18),
    tok03(Identifier, "b", 2, 25),
    tok03(Semicolon, ";", 2, 26),
    tok03(RBrace, "}", 2, 28),
    tok03(Identifier, "u", 2, 30),
    tok03(Semicolon, ";", 2, 31),
    tok03(RBrace, "}", 3, 1),
    tok03(Semicolon, ";", 3, 2),
    tok03(Eof, "", 3, 3),
  ]
  let p = Parser::with_mode(toks, false)
  let program : @ast.ProgramNode = {
    structs: [],
    unions: [],
    globals: [],
    funcs: [],
    classes: [],
    templates: [],
    template_instantiations: [],
  }
  p.dispatch_top_level(program, p.classify_top_level())
  let mut found_union_entry = false
  for entry in p.parsed_aggregates {
    if entry.1 {
      found_union_entry = true
    }
  }
  assert_true(
    found_union_entry,
    msg="嵌套 union 应以 is_union=true 记 parsed_aggregates（旧恒 false ⇒ E1006 折叠断链）",
  )
}
