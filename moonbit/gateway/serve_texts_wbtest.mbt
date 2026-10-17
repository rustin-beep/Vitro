///|
/// #130 批② 注入通道协议锚（2026-10-17）：`texts.install` 方法——
/// 浏览器宿主懒加载语言包后经协议装载（payload = 语言包 texts_json 同
/// schema）。批③a 起 gateway 测试态 = lean 载体（suggestions/builtin
/// 空 + trap 烘焙 45——gateway 禁 import content_data 否则烘焙数据
/// 进浏览器 wasm）；恢复纪律同 install_wbtest：凡装载即测尾回装
/// 原载荷（gateway 测试共享进程级表状态）。

///|
/// 正路：fixture 载荷（两建议 + 一 builtin——bubble_sort / quick_sort
/// 均在引擎侧 43 值域名单内；**trap 段缺席**=不碰引擎烘焙——批③a
/// 可选段语义）→ ok 帧带三表装后计数；trap 计数应保持烘焙 45。
test "serve_texts_install_roundtrip_ok" {
  let saved = @assets.texts_json()
  let fixture = Json::object({
    "suggestions": Json::object({
      "bubble_sort": Json::string("协议装载探针 A"),
      "quick_sort": Json::string("协议装载探针 B"),
    }),
    "builtin_notes": Json::object({
      "fread": Json::object({
        "count_note": Json::string("fread 装载探针"),
        "param_notes": Json::array([]),
      }),
    }),
    // 批③b 第四段：诊断卡片段（1001 ∈ catalog_codes 值域）
    "error_catalog": Json::object({
      "1001": Json::object({
        "icon": Json::string("unknown-char"),
        "title": Json::string("卡片段探针"),
        "explanation": Json::string("批③b 段分发探针"),
        "common_causes": Json::array([]),
      }),
    }),
  })
  // 载荷作为 JSON 字符串值嵌入——经 stringify 免手拼转义
  let params = Json::object({ "payload": Json::string(fixture.stringify()) })
  let line = "{\"id\":1,\"method\":\"texts.install\",\"params\":" +
    params.stringify() +
    "}"
  let s = @session.Session::new()
  let (resp, _) = serve_handle(s, line)
  assert_true(resp.contains("\"ok\":true"), msg="ok 帧实得：\{resp}")
  // 四表装后计数（2/1/45/1——trap 引擎烘焙不随 fixture 归零；批③b
  // 第四段计数）
  assert_true(resp.contains("\"suggestions\":2"), msg="计数面：\{resp}")
  assert_true(resp.contains("\"builtin_notes\":1"), msg="计数面：\{resp}")
  assert_true(resp.contains("\"trap_messages\":45"), msg="计数面：\{resp}")
  assert_true(
    resp.contains("\"error_catalog\":1"),
    msg="段计数面：\{resp}",
  )
  // 装载可见：建议值经载体查表即得 + 卡片段经 diag 载体即得
  assert_eq(
    @assets.suggestion_map.get("bubble_sort"),
    Some("协议装载探针 A"),
  )
  assert_true(
    @diag.ErrorCode::from_code(1001).unwrap().catalog() is Some(_),
    msg="卡片段装载后 catalog() 须命中",
  )
  // 回装原载荷（恢复 lean 基态——saved 无卡片段=diag 段不动，补空段复位）
  let restore = Json::object({ "payload": Json::string(saved) })
  let line2 = "{\"id\":9,\"method\":\"texts.install\",\"params\":" +
    restore.stringify() +
    "}"
  let (resp2, _) = serve_handle(@session.Session::new(), line2)
  assert_true(resp2.contains("\"ok\":true"), msg="恢复帧：\{resp2}")
  @diag.install_catalog_texts("{}") catch {
    _ => ()
  }
}

///|
/// fail loud：坏载荷 → error 帧带诊断（不落半装——表保持原状）。
test "serve_texts_install_bad_payload_error" {
  let saved = @assets.texts_json()
  let s = @session.Session::new()
  let (resp, _) = serve_handle(
    s, "{\"id\":2,\"method\":\"texts.install\",\"params\":{\"payload\":\"{not json\"}}",
  )
  assert_true(resp.contains("\"ok\":false"), msg="须 error 帧：\{resp}")
  assert_true(resp.contains("JSON"), msg="诊断须含失败因：\{resp}")
  // 不落半装：表原状
  assert_eq(@assets.texts_json(), saved)
}

///|
/// 参数面：缺 payload 键 → error 帧（protocol 形态错，禁静默 default）。
test "serve_texts_install_missing_param_error" {
  let s = @session.Session::new()
  let (resp, _) = serve_handle(
    s, "{\"id\":3,\"method\":\"texts.install\",\"params\":{}}",
  )
  assert_true(resp.contains("\"ok\":false"), msg="缺参须 error：\{resp}")
}
