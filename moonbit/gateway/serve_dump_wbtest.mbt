// serve dump 族白盒锚（S8 dump 接线批，2026-10-01）：三方法协议面 +
// 错误路径同构 + **只读契约机判锚**（dump 前后 session 状态零变——
// 2026-09-29 契约拍板的可执行形态）。wire 逐字节对拍留批四号
//（protocol_frames 双宿主——本族锁结构面）。

///|
test "serve_dump_ast_ok_path" {
  let s = @session.Session::new()
  let (r, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"ast.dump\",\"params\":{\"source\":\"int main() { return 1; }\\n\"}}",
  )
  assert_true(r.contains("\"ok\":true"))
  assert_true(r.contains("\"parse_error_count\":0"))
  assert_true(r.contains("\"ast\":{\"structs\""))
  assert_true(r.contains("\"stall_count\":0"))
}

///|
test "serve_dump_ast_lex_error_path" {
  let s = @session.Session::new()
  let (r, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"ast.dump\",\"params\":{\"source\":\"int main() { return 1 `$; }\\n\"}}",
  )
  assert_true(r.contains("\"ok\":false"))
  assert_true(r.contains("\"lex_error_count\":"))
  assert_true(r.contains("\"ast\":null"))
  assert_true(r.contains("\"parse_errors\":[]"))
}

///|
test "serve_dump_ast_parse_error_path" {
  let s = @session.Session::new()
  let (r, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"ast.dump\",\"params\":{\"source\":\"int main() { int a = ; }\\n\"}}",
  )
  // Rust 语义：ok 只随 program 是否 Some（错误恢复的占位 AST 同 ok:true
  // 且 parse_error_count 非空——锁明细而非极性；错误恢复可级联多报，
  // 不锁计数）
  assert_true(r.contains("\"parse_error_count\":"))
  assert_true(r.contains("\"parse_errors\":[{\"code\""))
  // 诊断明细四字段（E2 面：code/line/column/message 保序）
  assert_true(r.contains("\"code\""))
  assert_true(r.contains("\"line\""))
  assert_true(r.contains("\"column\""))
  assert_true(r.contains("\"message\""))
}

///|
test "serve_dump_typeck_ok_and_type_error" {
  let s = @session.Session::new()
  let (ok, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"typeck.dump\",\"params\":{\"source\":\"int main() { int a = 1; return a; }\\n\"}}",
  )
  assert_true(ok.contains("\"ok\":true"))
  assert_true(ok.contains("\"typed_ast\":{\"structs\""))
  assert_true(ok.contains("\"type_errors\":[]"))
  let (err, _) = serve_handle(
    s, "{\"id\":2,\"method\":\"typeck.dump\",\"params\":{\"source\":\"int main() { return x; }\\n\"}}",
  )
  assert_true(
    err.contains("\"ok\":true"),
    msg="类型错非阻断（type_errors 非空仍带 typed_ast）",
  )
  assert_true(err.contains("\"type_errors\":[{\"code\""))
}

///|
test "serve_dump_symbols_table" {
  let s = @session.Session::new()
  let (r, _) = serve_handle(
    s, "{\"id\":1,\"method\":\"symbols.dump\",\"params\":{\"source\":\"int g = 5;\\nint main() { int i = 1; return g + i; }\\n\"}}",
  )
  assert_true(r.contains("\"ok\":true"))
  assert_true(r.contains("\"count\":"))
  // 全局 g 与局部 i 均入表（name/addr/is_local/decl_line 四字段）
  assert_true(r.contains("\"name\":\"g\""))
  assert_true(r.contains("\"name\":\"i\""))
  assert_true(r.contains("\"is_local\":false"))
  assert_true(r.contains("\"is_local\":true"))
  assert_true(r.contains("\"decl_line\""))
}

///|
test "serve_dump_missing_source_protocol_error" {
  let s = @session.Session::new()
  for m in ["ast.dump", "typeck.dump", "symbols.dump"] {
    let (r, _) = serve_handle(s, "{\"id\":1,\"method\":\"\{m}\"}")
    assert_true(r.contains("\"kind\":\"protocol\""))
    assert_true(r.contains("需要 params.source"))
    // #68 连坐：expected 字段存在断言（dump 族形状 = source:string）
    assert_true(r.contains("\"expected\":\"source:string\""))
  }
}

///|
test "serve_dump_readonly_contract" {
  // 只读契约机判锚（2026-09-29 拍板）：dump 前后 session 编译态/诊断面
  // 零变——oracle 的 run_multi_file_pipeline 副作用（写 session 诊断）
  // 不照搬（已知限制 ④表）
  let s = @session.Session::new()
  // 先建立非平凡会话态：一次失败编译（诊断非空 + compiled=false）
  ignore(
    serve_handle(
      s, "{\"id\":1,\"method\":\"compile\",\"params\":{\"source\":\"int main() { return ; }\\n\"}}",
    ),
  )
  let diags_before = s.compile.diagnostics.length()
  let compiled_before = s.compile.compiled
  assert_true(diags_before > 0, msg="前置：编译失败诊断非空")
  assert_false(compiled_before)
  // 三 dump 全走一遍（成功 + 失败路径混合）
  ignore(
    serve_handle(
      s, "{\"id\":2,\"method\":\"ast.dump\",\"params\":{\"source\":\"int main() { return ; }\\n\"}}",
    ),
  )
  ignore(
    serve_handle(
      s, "{\"id\":3,\"method\":\"typeck.dump\",\"params\":{\"source\":\"int main() { return ; }\\n\"}}",
    ),
  )
  ignore(
    serve_handle(
      s, "{\"id\":4,\"method\":\"symbols.dump\",\"params\":{\"source\":\"int g = 1;\\nint main() { return g; }\\n\"}}",
    ),
  )
  // 会话态零变（诊断数 / compiled / 产物——dump 不写）
  assert_eq(s.compile.diagnostics.length(), diags_before)
  assert_eq(s.compile.compiled, compiled_before)
  assert_true(s.compile.output is None, msg="symbols.dump 不落产物")
}

///|
/// #418（W4 尾件批，2026-11-03）：合法深嵌套源码的 ast.dump 帧——
/// legal_deep 反向锚 paren_30_add_100 同族（30 层括号 + 100 项加法，
/// 仓内明文「合法深嵌套」）。修前：dump_parse_or_abort 自检上限 128
/// < 合法 AST 可达 JSON 深度 → 整实例 abort（wasm unreachable，W4 第四
/// 臂钉出）；修后：深路径文本直拼，帧出口完整可解析。
test "serve_dump_deep_ast_complete_frame" {
  // 源码自持构造（不依赖外部语料文件）
  let mut inner = "1"
  for i = 0; i < 100; i = i + 1 {
    inner = inner + " + 1"
  }
  let mut src = "int main() { return "
  for i = 0; i < 30; i = i + 1 {
    src = src + "("
  }
  src = src + inner
  for i = 0; i < 30; i = i + 1 {
    src = src + ")"
  }
  src = src + "; }"
  let s = @session.Session::new()
  let req = "{\"id\":7,\"method\":\"ast.dump\",\"params\":{\"source\":\"\{src}\"}}"
  let (r, _) = serve_handle(s, req)
  assert_true(r.contains("\"ok\":true"))
  // 深路径直拼 emitter 原文（带空格形态——浅路径紧凑化的分叉口径，#418 注）
  assert_true(r.contains("\"parse_error_count\": 0"))
  // 出口完整性：深路径文本直拼后的帧整体仍是合法 JSON（放宽深度上限
  // 解析回来——json_parse 的 depth_limit~ 通道参数即本断言的消费面）
  let frame = @util.json_parse(r, depth_limit=1000) catch {
    _ => fail("ast.dump 深嵌套帧不可解析（#418 回归）")
  }
  let result = json_field(frame, "result")
  assert_true(
    json_field(result, "ast") is Object(_),
    msg="result.ast 在场且为对象",
  )
}

///|
/// #418 续：typeck.dump 深嵌套帧同修（dump 族四帧同形——W4 §4.3(a)
/// ast.dump 与 typeck.dump 两侧同 trap）；同一源码 typeck 干净路径。
test "serve_dump_deep_typeck_complete_frame" {
  let mut inner = "1"
  for i = 0; i < 100; i = i + 1 {
    inner = inner + " + 1"
  }
  let mut src = "int main() { return "
  for i = 0; i < 30; i = i + 1 {
    src = src + "("
  }
  src = src + inner
  for i = 0; i < 30; i = i + 1 {
    src = src + ")"
  }
  src = src + "; }"
  let s = @session.Session::new()
  let req = "{\"id\":8,\"method\":\"typeck.dump\",\"params\":{\"source\":\"\{src}\"}}"
  let (r, _) = serve_handle(s, req)
  assert_true(r.contains("\"ok\":true"))
  let frame = @util.json_parse(r, depth_limit=1000) catch {
    _ => fail("typeck.dump 深嵌套帧不可解析（#418 回归）")
  }
  let result = json_field(frame, "result")
  assert_true(
    json_field(result, "typed_ast") is Object(_),
    msg="result.typed_ast 在场且为对象",
  )
}

///|
/// #418 单元锚：json_structural_depth 扫描器口径——配平/字符串感知/
/// 转义感知（扫描器是深路径唯一的结构防线，独立白盒锁定）。
test "json_structural_depth_scanner" {
  assert_eq(json_structural_depth("{}"), 1)
  assert_eq(json_structural_depth("[{}]"), 2)
  assert_eq(json_structural_depth("{\"a\":[{\"b\":1}]}"), 3)
  // 字符串内的括号不计
  assert_eq(json_structural_depth("{\"a\":\"}{[\"}"), 1)
  // 转义引号不闭合字符串
  assert_eq(json_structural_depth("{\"a\":\"\\\"[\"}"), 1)
  // 配平破 / 字符串未闭合 → -1
  assert_eq(json_structural_depth("{"), -1)
  assert_eq(json_structural_depth("}"), -1)
  assert_eq(json_structural_depth("{\"a\":1"), -1)
  assert_eq(json_structural_depth("{\"a\":\"x}"), -1)
}
