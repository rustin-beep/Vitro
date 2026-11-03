// mcp 白盒测试（DSH mbt 化批，2026-11-03）：全 12 工具走桩 Host（可拨假钟 +
// 渲染钩子可检入参）——协议层/披露/池/投影/推进语义在此锁当前行为。
// 语料 = 紧凑冒泡（与 v1 samples/bubble.c 同数据 {5,2,8,1,9,3}——逆序对 7 =
// swap 事件数锚）。

///|
/// 可拨假钟。
fn fake_host(clock : Ref[Double], rendered : Ref[Json]?) -> Host {
  {
    clock_ms: () => clock.val,
    render: data => {
      match rendered {
        Some(r) => r.val = data
        None => ()
      }
      ob()
      .b("ok", true)
      .s("html_path", "/tmp/vitro-test/out.html")
      .n("size_bytes", 12345)
      .n("frame_count", jarr(jget(data, "frames")).length())
      .s("mode_used", jstr_or(jget(data, "mode"), "static"))
      .done()
    },
  }
}

///|
/// v1 samples/bubble.c 逐字同源（锚：1126 步 / swap 7 = 逆序对 / compare 54 /
/// 首交换帧 93 行 8 / stdout "1 2 3 5 8 9 \n"——js 产物烟测 2026-11-03 实测）。
fn bubble_src() -> String {
  "#include <stdio.h>\n\nvoid bubble_sort(int arr[], int n) {\n    for (int i = 0; i < n - 1; i++) {\n        for (int j = 0; j < n - 1 - i; j++) {\n            if (arr[j] > arr[j + 1]) {\n                int tmp = arr[j];\n                arr[j] = arr[j + 1];\n                arr[j + 1] = tmp;\n            }\n        }\n    }\n}\n\nint main(void) {\n    int arr[6] = {5, 2, 8, 1, 9, 3};\n    bubble_sort(arr, 6);\n    for (int i = 0; i < 6; i++) printf(\"%d \", arr[i]);\n    printf(\"\\n\");\n    return 0;\n}\n"
}

///|
fn call(srv : Server, method_name : String, id : Int32) -> Json {
  let line = ob()
    .s("jsonrpc", "2.0")
    .n("id", id)
    .s("method", method_name)
    .done()
    .stringify()
  let out = srv.handle_line(line)
  guard out.length() >= 1 else { abort("无响应帧") }
  @util.json_parse(out[0]) catch {
    _ => abort("响应非 JSON")
  }
}

///|
fn tool_call(
  srv : Server,
  id : Int32,
  name : String,
  arguments_ : Json,
) -> Json {
  let line = ob()
    .s("jsonrpc", "2.0")
    .n("id", id)
    .s("method", "tools/call")
    .j("params", ob().s("name", name).j("arguments", arguments_).done())
    .done()
    .stringify()
  let out = srv.handle_line(line)
  guard out.length() >= 1 else { abort("无响应帧") }
  @util.json_parse(out[0]) catch {
    _ => abort("响应非 JSON")
  }
}

///|
/// tools/call 成功体（content[0].text 解出的工具 JSON）。
fn tool_body(resp : Json) -> Json {
  let content = jarr(jget(jget(resp, "result"), "content"))
  guard content.length() >= 1 else { abort("无 content: \{resp.stringify()}") }
  let text = jstr_or(jget(content[0], "text"), "")
  @util.json_parse(text) catch {
    _ => abort("工具返回体非 JSON: \{text[0:120].to_owned()}")
  }
}

///|
test "mcp_protocol_basics" {
  let clock : Ref[Double] = Ref(0.0)
  let srv = Server::new(host=fake_host(clock, None))
  // initialize：listChanged 契约 + serverInfo
  let init = call(srv, "initialize", 1)
  assert_true(
    jbool(
      jget(
        jget(jget(jget(init, "result"), "capabilities"), "tools"),
        "listChanged",
      ),
    ) ==
    Some(true),
    msg="initialize 须声明 tools.listChanged=true",
  )
  assert_eq(
    jstr_or(jget(jget(init, "result"), "protocolVersion"), ""),
    "2025-03-26",
    msg="缺省协议版本",
  )
  // ping
  assert_true(call(srv, "ping", 2) is Object(_), msg="ping 回空对象")
  // 未知方法 → -32601
  let unk = call(srv, "nope", 3)
  assert_eq(
    jint(jget(jget(unk, "error"), "code")),
    Some(-32601),
    msg="未知方法 -32601",
  )
  // 非法 JSON → -32700（id null）
  let bad = srv.handle_line("{not json")
  assert_eq(bad.length(), 1, msg="非法 JSON 一帧错误")
  let parsed = @util.json_parse(bad[0]) catch { _ => abort("x") }
  assert_eq(
    jint(jget(jget(parsed, "error"), "code")),
    Some(-32700),
    msg="Parse error -32700",
  )
  // 未知工具 → -32602
  let ut = tool_call(srv, 4, "no_such_tool", Json::object(Map([])))
  assert_eq(
    jint(jget(jget(ut, "error"), "code")),
    Some(-32602),
    msg="未知工具 -32602",
  )
}

///|
test "mcp_disclosure_flow" {
  let clock : Ref[Double] = Ref(0.0)
  let srv = Server::new(host=fake_host(clock, None))
  ignore(call(srv, "initialize", 1))
  // L0：5 工具（session_open 是解锁触发器，必须无会话可见）
  let list0 = call(srv, "tools/list", 2)
  let names0 = jarr(jget(jget(list0, "result"), "tools"))
  assert_eq(names0.length(), 5, msg="L0 可见 5 工具")
  assert_eq(
    jstr_or(jget(names0[4], "name"), ""),
    "session_open",
    msg="第 5 个是 session_open",
  )
  // readOnlyHint：diagnose/capabilities/sessions true；animate/session_open false
  assert_eq(
    jbool(jget(jget(names0[1], "annotations"), "readOnlyHint")),
    Some(true),
    msg="diagnose readOnlyHint=true",
  )
  assert_eq(
    jbool(jget(jget(names0[0], "annotations"), "readOnlyHint")),
    Some(false),
    msg="animate readOnlyHint=false",
  )
  // L1 调用在无会话时 → 工具级可操作错误（isError:true）
  let guard_resp = tool_call(srv, 3, "frames_summary", Json::object(Map([])))
  assert_eq(
    jbool(jget(jget(guard_resp, "result"), "isError")),
    Some(true),
    msg="无会话调 L1 → isError",
  )
  let guard_text = jstr_or(
    jget(jarr(jget(jget(guard_resp, "result"), "content"))[0], "text"),
    "",
  )
  assert_true(
    guard_text.contains("session_open"),
    msg="守卫文案指向 session_open",
  )
  // session_open → 响应 + list_changed 通知
  let open_line = ob()
    .s("jsonrpc", "2.0")
    .n("id", 4)
    .s("method", "tools/call")
    .j(
      "params",
      ob()
      .s("name", "session_open")
      .j("arguments", ob().s("source", bubble_src()).done())
      .done(),
    )
    .done()
    .stringify()
  let out = srv.handle_line(open_line)
  assert_eq(out.length(), 2, msg="session_open 出响应+通知两帧")
  let notif = @util.json_parse(out[1]) catch { _ => abort("通知非 JSON") }
  assert_eq(
    jstr_or(jget(notif, "method"), ""),
    "notifications/tools/list_changed",
    msg="第二帧是 list_changed",
  )
  let body = tool_body(
    @util.json_parse(out[0]) catch {
      _ => abort("响应非 JSON")
    },
  )
  assert_eq(
    jstr_or(jget(body, "session_id"), ""),
    "s_0001",
    msg="会话 id 序号",
  )
  assert_eq(jbool(jget(body, "compile_ok")), Some(true), msg="编译成功")
  // L1 出现：12 工具
  let list1 = call(srv, "tools/list", 5)
  assert_eq(
    jarr(jget(jget(list1, "result"), "tools")).length(),
    12,
    msg="L1 全量 12 工具",
  )
  // 关闭 → 收回 + 通知
  let close_line = ob()
    .s("jsonrpc", "2.0")
    .n("id", 6)
    .s("method", "tools/call")
    .j(
      "params",
      ob()
      .s("name", "session_close")
      .j("arguments", Json::object(Map([])))
      .done(),
    )
    .done()
    .stringify()
  let out2 = srv.handle_line(close_line)
  assert_eq(out2.length(), 2, msg="session_close 出响应+通知两帧")
  let list2 = call(srv, "tools/list", 7)
  assert_eq(
    jarr(jget(jget(list2, "result"), "tools")).length(),
    5,
    msg="收回后回到 L0 5 工具",
  )
}

///|
test "mcp_pool_lru_evict" {
  let clock : Ref[Double] = Ref(0.0)
  let srv = Server::new(host=fake_host(clock, None))
  ignore(call(srv, "initialize", 1))
  // 开 9 个会话（池上限 8）——第 9 个触发第 1 个逐出
  for i = 1; i <= 9; i = i + 1 {
    clock.val = i.to_double()
    let resp = tool_call(
      srv,
      100 + i,
      "session_open",
      ob().s("source", bubble_src()).done(),
    )
    if i == 9 {
      let body = tool_body(resp)
      let ev = jstr_arr(jget(body, "evicted_sessions"))
      assert_eq(ev.length(), 1, msg="第 9 会话逐出 1 个")
      assert_eq(ev[0], "s_0001", msg="逐出最久未用（s_0001）")
    }
  }
  // s_0001 已死：指向它返回可操作错误（isError，content 纯文本）
  let dead = tool_call(
    srv,
    200,
    "frames_summary",
    ob().s("session_id", "s_0001").done(),
  )
  assert_eq(
    jbool(jget(jget(dead, "result"), "isError")),
    Some(true),
    msg="死会话 isError",
  )
  let text = jstr_or(
    jget(jarr(jget(jget(dead, "result"), "content"))[0], "text"),
    "",
  )
  assert_true(
    text.contains("不存在或已过期"),
    msg="死会话错误文案可操作",
  )
  // s_0002 仍活（isError:false 且返回体是 JSON）
  let alive = tool_call(
    srv,
    201,
    "frames_summary",
    ob().s("session_id", "s_0002").done(),
  )
  assert_eq(
    jbool(jget(jget(alive, "result"), "isError")),
    Some(false),
    msg="s_0002 存活",
  )
}

///|
test "mcp_pool_ttl_expiry" {
  let clock : Ref[Double] = Ref(0.0)
  let srv = Server::new(host=fake_host(clock, None))
  ignore(call(srv, "initialize", 1))
  clock.val = 1000.0
  ignore(
    tool_call(srv, 1, "session_open", ob().s("source", bubble_src()).done()),
  )
  // 5 分钟内：存活（expires_in_s > 0）
  clock.val = 1000.0 + 200000.0
  let sessions = tool_body(tool_call(srv, 2, "sessions", Json::object(Map([]))))
  let arr = jarr(jget(sessions, "sessions"))
  assert_eq(arr.length(), 1, msg="TTL 内 1 会话")
  assert_eq(jint(jget(arr[0], "expires_in_s")), Some(100), msg="剩余 100s")
  // 过 5 分钟：下一次任意请求逐出 + 披露收回（通知帧）
  clock.val = 1000.0 + 300001.0
  let out = srv.handle_line(
    ob().s("jsonrpc", "2.0").n("id", 3).s("method", "ping").done().stringify(),
  )
  assert_eq(
    out.length(),
    2,
    msg="过期逐出触发 list_changed（ping 响应+通知）",
  )
  let sessions2 = tool_body(
    tool_call(srv, 4, "sessions", Json::object(Map([]))),
  )
  assert_eq(
    jarr(jget(sessions2, "sessions")).length(),
    0,
    msg="过期后池空",
  )
}

///|
test "mcp_frames_summary_bubble_anchor" {
  let clock : Ref[Double] = Ref(0.0)
  let srv = Server::new(host=fake_host(clock, None))
  ignore(call(srv, "initialize", 1))
  ignore(
    tool_call(srv, 1, "session_open", ob().s("source", bubble_src()).done()),
  )
  let body = tool_body(
    tool_call(srv, 2, "frames_summary", Json::object(Map([]))),
  )
  let s = jget(body, "summary")
  // 当前行为锚：v1 实测口径（1126 原始步 / swap 7 = 逆序对数 / compare 54）
  assert_eq(
    jint(jget(s, "total")),
    Some(1126),
    msg="总帧数锚（v1 同源）",
  )
  assert_eq(
    jint(jget(jget(s, "vis_events"), "swap")),
    Some(7),
    msg="swap 事件 = 逆序对数",
  )
  assert_eq(jstr_or(jget(s, "stopped"), ""), "finished", msg="终局")
  let outs = jget(body, "outputs")
  assert_eq(
    jstr_or(jget(outs, "stdout"), ""),
    "1 2 3 5 8 9 \n",
    msg="stdout 锚（v1 同源）",
  )
}

///|
test "mcp_frames_query_projection_and_paging" {
  let clock : Ref[Double] = Ref(0.0)
  let srv = Server::new(host=fake_host(clock, None))
  ignore(call(srv, "initialize", 1))
  ignore(
    tool_call(srv, 1, "session_open", ob().s("source", bubble_src()).done()),
  )
  // 默认投影：只有 i/l/f/s（无 r）
  let q = tool_body(
    tool_call(srv, 2, "frames_query", ob().n("limit", 5).done()),
  )
  assert_eq(jint(jget(q, "total")), Some(1126), msg="过滤后全量")
  let frames = jarr(jget(q, "frames"))
  assert_eq(frames.length(), 5, msg="limit 5")
  let f0 = match frames[0] {
    Object(m) => m
    _ => abort("帧非对象")
  }
  let mut has_r = false
  for k, _ in f0 {
    if k == "r" || k == "v" || k == "c" || k == "e" || k == "a" || k == "h" {
      has_r = true
    }
  }
  assert_false(has_r, msg="默认投影不含扩展字段")
  assert_true(jbool(jget(q, "has_more")) == Some(true), msg="has_more")
  // fields=r + filter has_vis_event
  let q2 = tool_body(
    tool_call(
      srv,
      3,
      "frames_query",
      ob()
      .j("fields", jstrs(["r"]))
      .j("filter", ob().b("has_vis_event", true).done())
      .n("limit", 50)
      .done(),
    ),
  )
  assert_eq(jint(jget(q2, "total")), Some(54 + 7), msg="含可视事件帧数")
  let fr = jarr(jget(q2, "frames"))[0]
  assert_true(
    match jget(fr, "r") {
      Object(_) => true
      _ => false
    },
    msg="fields=r 给出数组快照",
  )
  // 分页边界：from 越界钳到 total、to 不含
  let q3 = tool_body(
    tool_call(srv, 4, "frames_query", ob().n("from", 1120).done()),
  )
  assert_eq(jint(jget(q3, "from")), Some(1120), msg="from 钳界")
  assert_eq(jint(jget(q3, "to")), Some(1126), msg="to=总帧数（不含）")
  // limit 越界 → -32602
  let bad = tool_call(srv, 5, "frames_query", ob().n("limit", 51).done())
  assert_eq(
    jint(jget(jget(bad, "error"), "code")),
    Some(-32602),
    msg="limit>50 协议错",
  )
}

///|
test "mcp_run_to_breakpoint_and_event" {
  let clock : Ref[Double] = Ref(0.0)
  let srv = Server::new(host=fake_host(clock, None))
  ignore(call(srv, "initialize", 1))
  ignore(
    tool_call(srv, 1, "session_open", ob().s("source", bubble_src()).done()),
  )
  // bubble.c 行 8 = 交换体（arr[j] = arr[j+1]）
  let ev = tool_body(
    tool_call(srv, 2, "run_to", ob().s("stop_event", "swap").done()),
  )
  assert_true(
    jint(jget(ev, "event_step")) == Some(93),
    msg="首个 swap 帧 93",
  )
  assert_true(jint(jget(ev, "paused_at")) == Some(8), msg="停在交换行 8")
  assert_true(
    match jint(jget(ev, "advanced")) {
      Some(n) => n > 0
      None => false
    },
    msg="有推进",
  )
  // 断点行推进（行 8）
  let bp = tool_body(
    tool_call(srv, 3, "run_to", ob().n("breakpoint_line", 8).done()),
  )
  assert_true(jint(jget(bp, "paused_at")) == Some(8), msg="断点行暂停")
  // 推进到终局
  let fin = tool_body(
    tool_call(srv, 4, "run_to", ob().n("max_frames", 20000).done()),
  )
  assert_eq(jstr_or(jget(fin, "stopped"), ""), "finished", msg="终局")
  // 终局后再 run_to → 提示回看
  let again = tool_body(
    tool_call(srv, 5, "run_to", ob().s("stop_event", "swap").done()),
  )
  assert_eq(jint(jget(again, "advanced")), Some(0), msg="终局零推进")
  assert_true(
    jstr_or(jget(again, "next"), "").contains("frames_query"),
    msg="终局提示回看",
  )
}

///|
test "mcp_step_next_keyframes" {
  let clock : Ref[Double] = Ref(0.0)
  let srv = Server::new(host=fake_host(clock, None))
  ignore(call(srv, "initialize", 1))
  ignore(
    tool_call(srv, 1, "session_open", ob().s("source", bubble_src()).done()),
  )
  let sn = tool_body(tool_call(srv, 2, "step_next", ob().n("n", 3).done()))
  assert_eq(jint(jget(sn, "keyframes")), Some(3), msg="3 个关键帧")
  let frames = jarr(jget(sn, "frames"))
  assert_eq(frames.length(), 3, msg="返回 3 帧（紧凑投影）")
  assert_true(
    match jint(jget(sn, "advanced")) {
      Some(n) => n > 0
      None => false
    },
    msg="有原始步推进",
  )
  // 终局后 step_next → 回看提示
  ignore(tool_call(srv, 3, "run_to", ob().n("max_frames", 20000).done()))
  let sn2 = tool_body(tool_call(srv, 4, "step_next", ob().n("n", 1).done()))
  assert_eq(jint(jget(sn2, "keyframes")), Some(0), msg="终局零关键帧")
}

///|
test "mcp_annotations_swap_pairs" {
  let clock : Ref[Double] = Ref(0.0)
  let srv = Server::new(host=fake_host(clock, None))
  ignore(call(srv, "initialize", 1))
  ignore(
    tool_call(srv, 1, "session_open", ob().s("source", bubble_src()).done()),
  )
  let an = tool_body(
    tool_call(srv, 2, "annotations", ob().s("kind", "swap").done()),
  )
  let ann = jget(an, "annotations")
  assert_eq(jint(jget(ann, "total")), Some(7), msg="swap 事件 7")
  let evs = jarr(jget(ann, "events"))
  let pair0 = jarr(jget(evs[0], "pair"))
  assert_eq(jint(pair0[0]), Some(0), msg="首交换对 [0,1] 下界")
  assert_eq(jint(pair0[1]), Some(1), msg="首交换对 [0,1] 上界")
  // call/return 事件族也在（main 入口深度变化等）
  let all = tool_body(tool_call(srv, 3, "annotations", Json::object(Map([]))))
  let total_all = jint(jget(jget(all, "annotations"), "total"))
  assert_true(
    match total_all {
      Some(n) => n > 7
      None => false
    },
    msg="全量事件 > swap 数",
  )
}

///|
test "mcp_render_stub_contract" {
  let clock : Ref[Double] = Ref(0.0)
  let rendered : Ref[Json] = Ref(Json::null())
  let srv = Server::new(host=fake_host(clock, Some(rendered)))
  ignore(call(srv, "initialize", 1))
  // animate（临时会话）→ 桩渲染收到的 data 契约
  let anim = tool_body(
    tool_call(
      srv,
      1,
      "animate",
      ob()
      .s("source", bubble_src())
      .n("budget", 100)
      .s("title", "测试动画")
      .done(),
    ),
  )
  assert_eq(jbool(jget(anim, "ok")), Some(true), msg="animate ok")
  assert_true(
    match jint(jget(anim, "frame_count")) {
      Some(n) => n > 50
      None => false
    },
    msg="关键帧数 > 50（budget 100）",
  )
  assert_eq(
    jint(jget(anim, "raw_step_count")),
    Some(1126),
    msg="原始步数锚",
  )
  let data = rendered.val
  assert_eq(
    jstr_or(jget(data, "title"), ""),
    "测试动画",
    msg="title 透传",
  )
  assert_eq(jstr_or(jget(data, "mode"), ""), "static", msg="缺省 static")
  assert_eq(
    jstr_or(jget(data, "slug"), ""),
    "bubble_sort",
    msg="识别算法 slug=bubble_sort",
  )
  assert_true(
    jarr(jget(data, "frames")).length() > 50,
    msg="帧数据进钩子",
  )
  assert_eq(
    jstr_or(jget(jget(data, "outputs"), "stdout"), ""),
    "1 2 3 5 8 9 \n",
    msg="输出透传",
  )
  // 编译失败：仍走渲染（诊断卡）+ warnings 带诊断行
  let badsrc = "int main(){int x = 5"
  let bad = tool_body(
    tool_call(srv, 2, "animate", ob().s("source", badsrc).done()),
  )
  assert_eq(jbool(jget(bad, "ok")), Some(false), msg="编译失败 ok=false")
  assert_eq(jint(jget(bad, "frame_count")), Some(0), msg="零帧")
  assert_true(
    jstr_arr(jget(bad, "warnings")).length() > 0,
    msg="warnings 带诊断行",
  )
}

///|
test "mcp_diagnose_e2005" {
  let clock : Ref[Double] = Ref(0.0)
  let srv = Server::new(host=fake_host(clock, None))
  ignore(call(srv, "initialize", 1))
  let d = tool_body(
    tool_call(
      srv,
      1,
      "diagnose",
      ob().s("source", "int main(){int x = 5").done(),
    ),
  )
  assert_eq(jbool(jget(d, "ok")), Some(false), msg="编译失败")
  let diags = jarr(jget(d, "diagnostics"))
  assert_true(diags.length() > 0, msg="有诊断")
  assert_eq(
    jstr_or(jget(diags[0], "code"), ""),
    "E2005",
    msg="E2005 锚（v1 同源）",
  )
  assert_true(
    jstr(jget(diags[0], "fix_suggestion")) is Some(_),
    msg="带修复建议",
  )
}

///|
test "mcp_capabilities_disclosure_section" {
  let clock : Ref[Double] = Ref(0.0)
  let srv = Server::new(host=fake_host(clock, None))
  ignore(call(srv, "initialize", 1))
  let c = tool_body(tool_call(srv, 1, "capabilities", Json::object(Map([]))))
  let pd = jget(c, "progressive_disclosure")
  assert_eq(
    jarr(jget(pd, "available_now")).length(),
    5,
    msg="available_now 5（L0）",
  )
  assert_eq(
    jstr_or(jget(pd, "unlocked_by"), ""),
    "session_open(source)",
    msg="unlocked_by",
  )
  assert_eq(jarr(jget(pd, "unlocks")).length(), 7, msg="unlocks 7（L1）")
  assert_eq(
    jstr_or(jget(pd, "state"), ""),
    "L0（无会话）",
    msg="初始态",
  )
}
