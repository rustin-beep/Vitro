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
    // PR #457 审阅 v2 P3-③：files[].source 同受 64KB 上限（修前只查顶层
    // source——files 通道绕过校验，70KB 编译成功）
    if jstr_or(jget(f, "source"), "").length() > 65536 {
      return Err(
        Proto(
          -32602, "files[].source 超限（>64KB/文件）——请精简用例",
        ),
      )
    }
  }
  // PR #457 审阅 P3：files 与 source 互斥 fail loud（旧形态 source 被静默忽略）
  if files.length() > 0 && source.length() > 0 {
    return Err(
      Proto(
        -32602, "参数 source 与 files 互斥——多文件工程只给 files（filename 含 \"main\" 者为主文件，缺省名 main.c）",
      ),
    )
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
/// 主文件挑选谓词（source_display 与 overview 的 offset 映射同源消费——
/// 两处漂移即行号对不齐）：filename 含 "main" 者优先，否则首个（与引擎
/// compile{files} 的 main.c 缺省名同源）。
fn main_file_pick(prev_picked : Bool, name : String) -> Bool {
  !prev_picked || name.contains("main")
}

///|
/// 程序概览（typeck.dump 函数表——只读通道不碰会话态；行区间 = 本函数起行
/// 到下一函数起行-1，末函数到文末）。
fn overview_json(e : Entry, source : String) -> Json {
  // PR #457 审阅 v2 P2-2：多文件工程行号与帧行号同基（引擎拼接坐标）——
  // 修前主文件单源重跑 typeck.dump 出单文件坐标，agent 按 overview 调
  // filter.line / run_to{breakpoint_line} 会静默空集。offset 取 compile
  // 出口 file_ranges 的主文件区间（gateway merge_units 生产者），末函数
  // 基准与 line_count 用拼接流全行数；单文件形态 offset=0 坐标不变。
  let (offset, main_end, lc) = {
    let ranges = jarr(jget(e.compile_result, "file_ranges"))
    if ranges.length() > 0 {
      let mut total = 0
      let mut picked : Json? = None
      for fr in ranges {
        let name = jstr_or(jget(fr, "filename"), "main.c")
        if main_file_pick(picked is Some, name) {
          picked = Some(fr)
        }
        let endl = jint_or(jget(fr, "end_line"), 0)
        if endl > total {
          total = endl
        }
      }
      match picked {
        Some(fr) =>
          (
            jint_or(jget(fr, "start_line"), 1) - 1,
            jint_or(jget(fr, "end_line"), 0),
            total,
          )
        None => (0, 0, total)
      }
    } else {
      let n = line_count(source)
      (0, n, n)
    }
  }
  let funcs : Array[(String, Int32)] = []
  match entry_call(e, "typeck.dump", ob().s("source", source).done()) {
    Ok(r) =>
      for f in jarr(jget(jget(r, "typed_ast"), "funcs")) {
        let line = jint_or(jget(jget(f, "loc"), "line"), 0)
        let has_body = !jis_null(jget(f, "body"))
        if line > 0 && has_body {
          funcs.push((jstr_or(jget(f, "name"), ""), line + offset))
        }
      }
    Err(_) => ()
  }
  funcs.sort_by((a, b) => a.1 - b.1)
  let arr : Array[Json] = []
  for i, f in funcs {
    let end = if i + 1 < funcs.length() { funcs[i + 1].1 - 1 } else { main_end }
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
  // PR #457 审阅 P2-1：files 多文件形态下 Entry.source 不能为空（overview
  // 的函数表/行数与 render 的源码面板都吃它）——取主文件源（main_file_pick
  // 谓词与 overview 的 offset 映射同源）
  let source_display = if files.length() > 0 {
    let mut pick = ""
    for f in files {
      let name = jstr_or(jget(f, "filename"), "main.c")
      if main_file_pick(pick.length() > 0, name) {
        pick = jstr_or(jget(f, "source"), "")
      }
    }
    pick
  } else {
    source
  }
  let e : Entry = {
    id,
    session: @session.Session::new(),
    seq: 0,
    title: jstr_or(jget(args, "title"), ""),
    source: source_display,
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
    overview_json(e, source_display)
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
