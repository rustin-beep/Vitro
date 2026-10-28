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
  // 回装（恢复 lean 基态——#323 合并语义下空段=不覆盖，saved 的空建议段
  // 无法再清场；改单帧显式 __clear__ 三段原子恢复。trap 未被 fixture
  // 触碰〔段缺席〕无需回装）
  let restore_payload = Json::object({
    "suggestions": Json::object({ "__clear__": Json::boolean(true) }),
    "builtin_notes": Json::object({ "__clear__": Json::boolean(true) }),
    "error_catalog": Json::object({ "__clear__": Json::boolean(true) }),
  })
  let restore = Json::object({
    "payload": Json::string(restore_payload.stringify()),
  })
  let line2 = "{\"id\":9,\"method\":\"texts.install\",\"params\":" +
    restore.stringify() +
    "}"
  let (resp2, _) = serve_handle(@session.Session::new(), line2)
  assert_true(resp2.contains("\"ok\":true"), msg="恢复帧：\{resp2}")
  assert_true(
    resp2.contains("\"suggestions\":0"),
    msg="恢复帧清空可观测（计数）:\{resp2}",
  )
}

///|
/// #323 读口（治①）：`texts.get` ——四表现值回读（texts.install 的
/// 读-改-写闭环读口；此前 30 方法无任何教学文案表读接口，下游无法
/// 自查键集 ⇒ 合法载荷不可构造）。get 的 result 原文回装 install
/// 须 ok 且再 get 逐字节同形（读-改-写闭环锚）。
test "serve_texts_get_read_interface" {
  let s = @session.Session::new()
  let (resp, _) = serve_handle(s, "{\"id\":11,\"method\":\"texts.get\"}")
  assert_true(
    resp.contains("\"ok\":true"),
    msg="texts.get 须 ok（读口缺位=协议闭环缺口 #323）：\{resp}",
  )
  assert_true(resp.contains("\"suggestions\""), msg="四段面：\{resp}")
  assert_true(resp.contains("\"builtin_notes\""), msg="四段面：\{resp}")
  assert_true(resp.contains("\"trap_messages\""), msg="四段面：\{resp}")
  assert_true(resp.contains("\"error_catalog\""), msg="四段面：\{resp}")
  // 读-改-写闭环：result（四段对象）stringify 回装 → ok；再 get 同形
  let parsed = @util.json_parse(resp) catch { _ => fail("get 帧解析失败") }
  let result = match parsed {
    Object(m) =>
      match m.get("result") {
        Some(r) => r
        None => fail("get 帧缺 result")
      }
    _ => fail("get 帧顶层形态异常")
  }
  let install_params = Json::object({
    "payload": Json::string(result.stringify()),
  })
  let line = "{\"id\":12,\"method\":\"texts.install\",\"params\":" +
    install_params.stringify() +
    "}"
  let (resp2, _) = serve_handle(@session.Session::new(), line)
  assert_true(
    resp2.contains("\"ok\":true"),
    msg="现值回装须 ok（get→install 闭环）：\{resp2}",
  )
  let (resp3, _) = serve_handle(
    @session.Session::new(),
    "{\"id\":11,\"method\":\"texts.get\"}",
  )
  assert_eq(resp3, resp, msg="回装后再 get 须逐字节同形")
}

///|
/// #323 合并语义（治②）：段级逐键覆盖——单段单键载荷合法（旧「顶层
/// 两必填 + trap 键集全等」下三连拒）；空段对象=不覆盖（旧=静默清空
/// 43 条教学建议卡）；`{"__clear__":true}` 显式清空并在响应 cleared
/// 数组回告（治④——清空类操作不再只回计数）。
test "serve_texts_install_merge_semantics" {
  let saved = @assets.texts_json()
  let saved_j = @util.json_parse(saved) catch {
    _ => fail("原载荷解析失败")
  }
  let saved_trap = match saved_j {
    Object(t) =>
      match t.get("trap_messages") {
        Some(tr) => tr
        None => fail("原载荷缺 trap 段")
      }
    _ => fail("原载荷顶层形态异常")
  }
  let inst = fn(id, payload : Json) -> String {
    let params = Json::object({ "payload": Json::string(payload.stringify()) })
    let line = "{\"id\":\{id},\"method\":\"texts.install\",\"params\":" +
      params.stringify() +
      "}"
    let (r, _) = serve_handle(@session.Session::new(), line)
    r
  }
  // ① 单段载荷：trap 一键覆盖（旧语义拒「顶层 1 键」与「键集不全等」）
  let r1 = inst(
    21,
    Json::object({
      "trap_messages": Json::object({
        "E3061_double_free": Json::object({
          "template": Json::string("合并探针 {freed_line}/{alloc_line}"),
          "placeholders": Json::array([
            Json::string("freed_line"),
            Json::string("alloc_line"),
          ]),
        }),
      }),
    }),
  )
  assert_true(r1.contains("\"ok\":true"), msg="单段单键须 ok：\{r1}")
  assert_eq(
    @assets.trap_messages.get("E3061_double_free").unwrap().template,
    "合并探针 {freed_line}/{alloc_line}",
    msg="逐键覆盖须可见",
  )
  assert_true(
    @assets.trap_messages.get("hint_uaf") is Some(_),
    msg="段内未提供键不得连坐（合并非替换）",
  )
  // ② 空段不清空：装 1 条建议后送空段对象 → 建议 1 保持（旧=清 0）
  let r2 = inst(
    22,
    Json::object({
      "suggestions": Json::object({
        "bubble_sort": Json::string("合并语义探针"),
      }),
    }),
  )
  assert_true(
    r2.contains("\"ok\":true"),
    msg="单段建议载荷须 ok：\{r2}",
  )
  let r3 = inst(
    23,
    Json::object({
      "suggestions": Json::object(Map([])),
      "builtin_notes": Json::object(Map([])),
    }),
  )
  assert_true(r3.contains("\"ok\":true"), msg="空段载荷须 ok：\{r3}")
  assert_true(
    r3.contains("\"suggestions\":1"),
    msg="空段不得清空（旧=静默清空教学表 #323-②）：\{r3}",
  )
  assert_eq(
    @assets.suggestion_map.get("bubble_sort"),
    Some("合并语义探针"),
  )
  // ③ 显式清空：__clear__ 单键段 → 清空 + cleared 数组回告
  let r4 = inst(
    24,
    Json::object({
      "suggestions": Json::object({ "__clear__": Json::boolean(true) }),
    }),
  )
  assert_true(r4.contains("\"ok\":true"), msg="__clear__ 须 ok：\{r4}")
  assert_true(
    r4.contains("\"suggestions\":0"),
    msg="显式清空须生效：\{r4}",
  )
  assert_true(
    r4.contains("\"cleared\":[\"suggestions\"]"),
    msg="清空须在 cleared 数组回告（#323-④）：\{r4}",
  )
  assert_true(@assets.suggestion_map.get("bubble_sort") is None)
  // ④ __clear__ 与数据键混用 → 拒（防半清空歧义形态）
  let r5 = inst(
    25,
    Json::object({
      "suggestions": Json::object({
        "__clear__": Json::boolean(true),
        "bubble_sort": Json::string("混用形态"),
      }),
    }),
  )
  assert_true(
    r5.contains("\"ok\":false"),
    msg="__clear__ 混用数据键须拒：\{r5}",
  )
  // 恢复：trap 全段回装（覆盖回原文）+ 建议表已清——单帧原子恢复
  let restore = Json::object({
    "trap_messages": saved_trap,
    "suggestions": Json::object({ "__clear__": Json::boolean(true) }),
    "builtin_notes": Json::object({ "__clear__": Json::boolean(true) }),
  })
  let r6 = inst(26, restore)
  assert_true(r6.contains("\"ok\":true"), msg="恢复帧：\{r6}")
  assert_eq(
    @assets.texts_json(),
    saved,
    msg="恢复后须回基态逐字节一致",
  )
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
