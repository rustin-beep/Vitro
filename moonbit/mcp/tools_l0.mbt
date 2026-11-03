// L0 永驻工具：animate / diagnose / capabilities / sessions（server.mbt 内联）
// / session_open。

///|
/// 源码参数校验（animate / diagnose / session_open 共用）。
fn arg_source(
  args : Json,
  allow_files : Bool,
) -> Result[(String, Array[Json]), ToolOut] {
  let source = jstr_or(jget(args, "source"), "")
  let files = if allow_files { jarr(jget(args, "files")) } else { [] }
  if source.length() == 0 && files.length() == 0 {
    return Err(
      Proto(
        -32602,
        if allow_files {
          "参数 source 必填（C 源码字符串）——或给 files（[{filename,source}]）"
        } else {
          "参数 source 必填（C 源码字符串）"
        },
      ),
    )
  }
  if source.length() > 65536 {
    return Err(Proto(-32602, "source 超限（>64KB）——请精简用例"))
  }
  for f in files {
    guard f is Object(_) else {
      return Err(Proto(-32602, "files 元素须为 {filename, source} 对象"))
    }
    if jstr(jget(f, "filename")) is None || jstr(jget(f, "source")) is None {
      return Err(
        Proto(-32602, "files 元素须为 {filename:string, source:string}"),
      )
    }
  }
  Ok((source, files))
}

///|
fn arg_preset(args : Json) -> Result[String, ToolOut] {
  let p = jstr_or(jget(args, "config_hint"), "default")
  if p == "default" || p == "algo" || p == "tiny" {
    Ok(p)
  } else {
    Err(Proto(-32602, "参数 config_hint 须为 default | algo | tiny"))
  }
}

///|
/// 算法识别投影（session_open 概览口径：剔 suggestion/vis_events/evidence，
/// 每项几十 token；diagnose 保留全量）。
fn algo_matches_proj(v : Json) -> Json {
  let arr : Array[Json] = []
  for m in jarr(v) {
    arr.push(
      ob()
      .s("name", jstr_or(jget(m, "name"), ""))
      .s("display_name", jstr_or(jget(m, "display_name"), ""))
      .s("func_name", jstr_or(jget(m, "func_name"), ""))
      .n("confidence", jint_or(jget(m, "confidence"), 0))
      .n("line", jint_or(jget(m, "line"), 0))
      .done(),
    )
  }
  Json::array(arr)
}

///|
fn first_algo(e : Entry) -> Json {
  let ms = jarr(jget(e.compile_result, "algorithm_matches"))
  if ms.length() == 0 {
    return Json::null()
  }
  let m = ms[0]
  ob()
  .s("name", jstr_or(jget(m, "name"), ""))
  .s("display_name", jstr_or(jget(m, "display_name"), ""))
  .n("confidence", jint_or(jget(m, "confidence"), 0))
  .n("line", jint_or(jget(m, "line"), 0))
  .done()
}

///|
/// 程序概览（typeck.dump 函数表——只读通道不碰会话态；行区间 = 本函数起行
/// 到下一函数起行-1，末函数到文末）。
fn overview_json(e : Entry, source : String) -> Json {
  let lc = line_count(source)
  let funcs : Array[(String, Int32)] = []
  match entry_call(e, "typeck.dump", ob().s("source", source).done()) {
    Ok(r) =>
      for f in jarr(jget(jget(r, "typed_ast"), "funcs")) {
        let line = jint_or(jget(jget(f, "loc"), "line"), 0)
        let has_body = !jis_null(jget(f, "body"))
        if line > 0 && has_body {
          funcs.push((jstr_or(jget(f, "name"), ""), line))
        }
      }
    Err(_) => ()
  }
  funcs.sort_by((a, b) => a.1 - b.1)
  let arr : Array[Json] = []
  for i, f in funcs {
    let end = if i + 1 < funcs.length() { funcs[i + 1].1 - 1 } else { lc }
    arr.push(ob().s("name", f.0).j("lines", jints([f.1, end])).done())
  }
  ob().n("line_count", lc).a("functions", arr).done()
}

///|
fn Server::tool_session_open(
  self : Server,
  args : Json,
  now : Double,
) -> ToolOut {
  let (source, files) = match arg_source(args, true) {
    Ok(v) => v
    Err(o) => return o
  }
  let preset = match arg_preset(args) {
    Ok(p) => p
    Err(o) => return o
  }
  let argv = jstr_arr(jget(args, "argv"))
  self.seq += 1
  let id = "s_" + pad4(self.seq)
  let e : Entry = {
    id,
    session: @session.Session::new(),
    seq: 0,
    title: jstr_or(jget(args, "title"), ""),
    source,
    argv,
    compile_result: Json::null(),
    frames: [],
    phase: PHASE_OPENED,
    run_result: Json::null(),
    stdout: "",
    stderr: "",
    paused_at: 0,
    trap_message: "",
    last_key: -1,
    opened_at: now,
    last_used: now,
  }
  let comp = match open_and_compile(e, source, files, preset) {
    Ok(c) => c
    Err(m) => return Fail("引擎编译通道失败：\{m}")
  }
  e.compile_result = comp
  let ok = jbool_or(jget(comp, "ok"), false)
  e.phase = if ok { PHASE_OPENED } else { PHASE_COMPILE_FAILED }
  let evicted = pool_insert(self.entries, e)
  let overview = if ok {
    overview_json(e, source)
  } else {
    ob().n("line_count", line_count(source)).done()
  }
  let body = ob()
    .s("session_id", id)
    .b("compile_ok", ok)
    .j("diagnostics", jget(comp, "diagnostics"))
    .j("algorithm_matches", algo_matches_proj(jget(comp, "algorithm_matches")))
    .j("overview", overview)
    .s(
      "next",
      if ok {
        "已解锁 L1：frames_summary 看结构 / annotations 找值得看的帧 / run_to·step_next 导游推进 / render 出 HTML / session_close 收尾"
      } else {
        "编译失败——按 diagnostics 修源后重新 session_open；本会话只能看诊断（render 可出诊断卡）"
      },
    )
  if evicted.length() > 0 {
    ignore(body.sa("evicted_sessions", evicted))
  }
  Done(tool_text(body.done()))
}

///|
fn Server::tool_diagnose(self : Server, args : Json, now : Double) -> ToolOut {
  let (source, _) = match arg_source(args, false) {
    Ok(v) => v
    Err(o) => return o
  }
  let eng : Entry = {
    id: "diag",
    session: @session.Session::new(),
    seq: 0,
    title: "",
    source,
    argv: [],
    compile_result: Json::null(),
    frames: [],
    phase: PHASE_OPENED,
    run_result: Json::null(),
    stdout: "",
    stderr: "",
    paused_at: 0,
    trap_message: "",
    last_key: -1,
    opened_at: now,
    last_used: now,
  }
  let comp = match open_and_compile(eng, source, [], "default") {
    Ok(c) => c
    Err(m) => return Fail("引擎编译通道失败：\{m}")
  }
  let ms = (self.now() - now).to_int()
  Done(
    tool_text(
      ob()
      .b("ok", jbool_or(jget(comp, "ok"), false))
      .j("diagnostics", jget(comp, "diagnostics"))
      .j("algorithm_matches", jget(comp, "algorithm_matches"))
      .n("ms", ms)
      .j("engine", engine_versions())
      .done(),
    ),
  )
}

///|
fn Server::tool_capabilities(self : Server) -> ToolOut {
  let l0 = tool_names(0)
  let l1 = tool_names(1)
  let now_avail = if self.l1_visible {
    let all = tool_names(0)
    for n in l1 {
      all.push(n)
    }
    all
  } else {
    l0
  }
  Done(
    tool_text(
      ob()
      .s("server", SERVER_NAME)
      .s("version", SERVER_VERSION)
      .j("engine", engine_versions())
      .s("mcp_protocol", MCP_PROTOCOL_VERSION)
      .j(
        "progressive_disclosure",
        ob()
        .sa("available_now", now_avail)
        .s("unlocked_by", "session_open(source)")
        .sa("unlocks", tool_names(1))
        .s(
          "state",
          if self.l1_visible {
            "L1 已解锁（有活跃会话）"
          } else {
            "L0（无会话）"
          },
        )
        .s(
          "when_to_use", "一次性出动画用 animate；教学引导/质量调优/批量编排先 session_open（解锁后会收到 tools/list_changed，请重拉 tools/list）",
        )
        .b("list_changed_notifications", true)
        .done(),
      )
      .j(
        "sessions",
        ob()
        .n("pool_max", POOL_CAP)
        .n("idle_ttl_s", (POOL_TTL_MS / 1000.0).to_int())
        .s(
          "addressing", "L1 工具带 session_id 参数；缺省 = 最近使用的会话",
        )
        .s(
          "isolation", "每会话独立引擎实例（同进程内 Session 隔离）；终局后不可回退推进，回看走 frames_query",
        )
        .done(),
      )
      .j(
        "read_only_tools",
        jstrs([
          "diagnose", "capabilities", "sessions", "frames_summary", "frames_query",
          "annotations",
        ]),
      )
      .j(
        "limits",
        jstrs([
          "单文件 C 源码 ≤64KB（或 files 多文件虚拟工程）", "stdin 交互程序会在 waiting_input 停（stopped 注明）",
          "采集上限 20000 引擎步/会话", "frames_query 每页 ≤50 帧；默认投影 {i,l,f,s}，fields 显式扩",
          "产物为本地 HTML 文件——需 present 或人工打开",
        ]),
      )
      .s(
        "dsh_usage", "mcp__vitro__animate(source) → html_path → present(files=[{path, description}]) 交付；会话流：session_open → frames_summary → annotations → render({from,to}) → present",
      )
      .done(),
    ),
  )
}

///|
/// animate = 编排糖：临时会话（不入池、不翻披露）+ 全量采集 + render。
fn Server::tool_animate(self : Server, args : Json, now : Double) -> ToolOut {
  let (source, _) = match arg_source(args, false) {
    Ok(v) => v
    Err(o) => return o
  }
  let eng : Entry = {
    id: "tmp",
    session: @session.Session::new(),
    seq: 0,
    title: "",
    source,
    argv: [],
    compile_result: Json::null(),
    frames: [],
    phase: PHASE_OPENED,
    run_result: Json::null(),
    stdout: "",
    stderr: "",
    paused_at: 0,
    trap_message: "",
    last_key: -1,
    opened_at: now,
    last_used: now,
  }
  let comp = match open_and_compile(eng, source, [], "default") {
    Ok(c) => c
    Err(m) => return Fail("引擎编译通道失败：\{m}")
  }
  eng.compile_result = comp
  let ok = jbool_or(jget(comp, "ok"), false)
  eng.phase = if ok { PHASE_OPENED } else { PHASE_COMPILE_FAILED }
  let e = eng
  if ok {
    match collect_all(e) {
      Ok(_) => ()
      Err(m) => return Fail("采集失败：\{m}")
    }
  }
  let ms_engine = (self.now() - now).to_int()
  self.render_entry(e, args, ms_engine)
}
