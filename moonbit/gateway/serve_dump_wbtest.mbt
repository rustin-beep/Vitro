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
  for m in ["ast.dump", "symbols.dump"] {
    let (r, _) = serve_handle(s, "{\"id\":1,\"method\":\"\{m}\"}")
    assert_true(r.contains("\"kind\":\"protocol\""))
    assert_true(r.contains("需要 params.source"))
    // #68 连坐：expected 字段存在断言（dump 族形状 = source:string）
    assert_true(r.contains("\"expected\":\"source:string\""))
  }
  // typeck.dump 的参数面扩为 files|source 二选一（DEF-1 2026-11-13）——
  // 空参数报错文案与 expected 形状连坐更新（对齐 compile 的双通道形态）
  let (r2, _) = serve_handle(s, "{\"id\":1,\"method\":\"typeck.dump\"}")
  assert_true(r2.contains("\"kind\":\"protocol\""))
  assert_true(r2.contains("需要 params.files"))
  assert_true(r2.contains("或 params.source"))
  assert_true(
    r2.contains(
      "\"expected\":\"files:[{filename?,source}] | source:string[,filename:string]\"",
    ),
  )
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

///|
/// #466 审阅 P1（2026-11-04）：dump_frame_ok 阈值边界锚——json_parse 的
/// depth 是递归栈深（末层标量也占一层），默认上限 128 实际只容**结构深度
/// ≤127** 走浅路径；`d <= 128` 会把 d=128 的合法帧送进浅路径 → 必然
/// 深度超限 → abort（越界一格，审阅实测 n=56 合法加法链 rc=0xC0000409）。
/// 阈值两侧各造一点（A1-c 教训：分界点外取样全绿≠无病）。
test "dump_frame_ok_threshold_boundary_466" {
  // 构造精确结构深度的合法 JSON：d-1 层 {"a": 嵌套 + 标量 1
  fn nested(depth : Int32) -> String {
    let buf = StringBuilder()
    for i = 0; i < depth - 1; i = i + 1 {
      buf.write_string("{\"a\":")
    }
    buf.write_string("1")
    for i = 0; i < depth - 1; i = i + 1 {
      buf.write_string("}")
    }
    buf.to_string()
  }
  // 口径对齐：文本含 k 个嵌套 `{` ⇒ json_structural_depth=k、json_parse
  // 栈深=k+1（末层标量占一层）。nested(n) 产出 k=n-1 个 `{`。
  // k=127（nested 128）：浅路径最后安全档（栈恰 128 = 上限内，全量自检）
  let f_shallow = dump_frame_ok(Json(7), nested(128))
  assert_true(
    f_shallow.contains("\"ok\":true"),
    msg="k=127 浅路径安全档正常",
  )
  // k=128（nested 129）：必须走深路径——浅路径栈深 129 > 128 必然拒绝
  //（修前 `d <= 128` 把它送进浅路径 abort，即审阅 P1 的越界一格；审阅
  // 端点复现 = 56 项加法链包 if，emitter 深度恰落此档 rc=0xC0000409）
  let f_deep = dump_frame_ok(Json(7), nested(129))
  assert_true(
    f_deep.contains("\"ok\":true"),
    msg="k=128 深路径正常（P1 越界一格）",
  )
  // 两侧帧均可解析回 Json（出口完整性）
  ignore(@util.json_parse(f_shallow, depth_limit=1000))
  ignore(@util.json_parse(f_deep, depth_limit=1000))
}

///|
/// #466 审阅 P2-1（2026-11-04）：深路径校验的**值级面**——升级前
/// json_structural_depth 只验括号配平，`{"a":01}` / 非法转义等坏值
/// 直拼出非法 JSON 帧（静默降级：把「能发现的崩溃」换成「静默坏帧」）。
/// 全部须判 -1（fail loud），与浅路径 json_parse 同强度。
test "json_lex_value_level_fail_loud_466" {
  // 数字文法（RFC 8259）：前导零 / 裸尾点 / 指数缺数 / 前导 + 号
  assert_eq(json_structural_depth("{\"a\":01}"), -1, msg="前导零")
  assert_eq(json_structural_depth("{\"a\":1.}"), -1, msg="裸尾点")
  assert_eq(json_structural_depth("[1e]"), -1, msg="指数缺数")
  assert_eq(json_structural_depth("[+1]"), -1, msg="前导加号")
  // 字符串域：非法转义 / u 转义非 hex / 裸控制字符
  assert_eq(json_structural_depth("\"x\\qy\""), -1, msg="非法转义")
  assert_eq(json_structural_depth("\"u\\u00ZZ\""), -1, msg="u 转义非 hex")
  assert_eq(json_structural_depth("\"a\nb\""), -1, msg="裸换行控制字符")
  // 字面量错拼 / 结构域（键非引号 / 缺逗号 / 尾逗号 / 顶层尾随）
  assert_eq(json_structural_depth("[tru]"), -1, msg="字面量错拼")
  assert_eq(json_structural_depth("{a:1}"), -1, msg="键非引号")
  assert_eq(json_structural_depth("[1 2]"), -1, msg="缺逗号")
  assert_eq(json_structural_depth("[1,]"), -1, msg="尾逗号")
  assert_eq(json_structural_depth("{\"a\":1,}"), -1, msg="对象尾逗号")
  assert_eq(json_structural_depth("1 x"), -1, msg="顶层尾随内容")
  // 合法形态回归（升级不得误伤）
  assert_eq(json_structural_depth("{\"a\":[{\"b\":1}]}"), 3)
  assert_eq(
    json_structural_depth("{\"a\":\"}{[\"}"),
    1,
    msg="字符串内括号不计",
  )
}
