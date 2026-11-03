// L1 会话工具：frames_summary / frames_query / annotations / run_to / step_next
// / render / session_close + render_entry（animate/render 共用渲染管线）。

///|
fn Server::tool_frames_summary(
  self : Server,
  args : Json,
  now : Double,
) -> ToolOut {
  let e = match self.resolve(args, now) {
    Ok(v) => v
    Err(m) => return Fail(m)
  }
  if e.phase == PHASE_OPENED {
    match collect_all(e) {
      Ok(_) => ()
      Err(m) => return Fail(m)
    }
  }
  Done(
    tool_text(
      ob()
      .s("session_id", e.id)
      .j("summary", summary_json(e.frames, e.stopped()))
      .j("outputs", outputs_json(e))
      .j("run", run_summary_json(e))
      .done(),
    ),
  )
}

///|
fn Server::tool_frames_query(
  self : Server,
  args : Json,
  now : Double,
) -> ToolOut {
  let e = match self.resolve(args, now) {
    Ok(v) => v
    Err(m) => return Fail(m)
  }
  if e.phase == PHASE_OPENED {
    match collect_all(e) {
      Ok(_) => ()
      Err(m) => return Fail(m)
    }
  }
  let limit = match jint(jget(args, "limit")) {
    Some(n) =>
      if n < 1 || n > 50 {
        return Proto(
          -32602, "参数 limit 须为 1..50（默认投影每页紧凑；全量数据用 fields 分页拉）",
        )
      } else {
        n
      }
    None => 50
  }
  let from = max_int(0, jint_or(jget(args, "from"), 0))
  let filter = jget(args, "filter")
  guard filter is Object(_) || jis_null(filter) else {
    return Proto(
      -32602, "参数 filter 须为对象 {label_prefix?, line?, func?, has_vis_event?}",
    )
  }
  let fields = jstr_arr(jget(args, "fields"))
  for f in fields {
    if !(f == "r" || f == "v" || f == "c" || f == "e" || f == "a" || f == "h") {
      return Proto(
        -32602,
        "fields 只认 r/v/c/e/a/h（默认恒给 i,l,f,s）——收到 '\{f}'",
      )
    }
  }
  // 先过滤后分页
  let idx : Array[Int32] = []
  for i, fr in e.frames {
    if frame_matches(fr, filter) {
      idx.push(i)
    }
  }
  let total = idx.length()
  let start = min_int(from, total)
  let end = min_int(
    match jint(jget(args, "to")) {
      Some(t) => t
      None => start + limit
    },
    total,
  )
  let arr : Array[Json] = []
  for k = start; k < end; k = k + 1 {
    arr.push(frame_json_proj(e.frames[idx[k]], fields))
  }
  Done(
    tool_text(
      ob()
      .s("session_id", e.id)
      .n("total", total)
      .n("from", start)
      .n("to", end)
      .b("has_more", end < total)
      .n("raw_total", e.frames.length())
      .a("frames", arr)
      .s("stopped", e.stopped())
      .done(),
    ),
  )
}

///|
fn Server::tool_annotations(
  self : Server,
  args : Json,
  now : Double,
) -> ToolOut {
  let e = match self.resolve(args, now) {
    Ok(v) => v
    Err(m) => return Fail(m)
  }
  if e.phase == PHASE_OPENED {
    match collect_all(e) {
      Ok(_) => ()
      Err(m) => return Fail(m)
    }
  }
  let kind = jstr_or(jget(args, "kind"), "")
  if !(kind.length() == 0 ||
    kind == "swap" ||
    kind == "compare" ||
    kind == "call" ||
    kind == "return") {
    return Proto(
      -32602, "参数 kind 须为 swap | compare | call | return（缺省全部）",
    )
  }
  Done(
    tool_text(
      ob()
      .s("session_id", e.id)
      .j("annotations", annotations_json(e.frames, kind))
      .done(),
    ),
  )
}

///|
fn Server::tool_run_to(self : Server, args : Json, now : Double) -> ToolOut {
  let e = match self.resolve(args, now) {
    Ok(v) => v
    Err(m) => return Fail(m)
  }
  if e.phase == PHASE_COMPILE_FAILED {
    return Fail(
      "会话编译失败——无帧可推进（修源后重新 session_open）",
    )
  }
  let bp = match jint(jget(args, "breakpoint_line")) {
    Some(l) =>
      if l < 1 {
        return Proto(
          -32602, "breakpoint_line 须为正整数（源码行号）",
        )
      } else {
        l
      }
    None => 0
  }
  let ev = jstr_or(jget(args, "stop_event"), "")
  if !(ev.length() == 0 || ev == "swap" || ev == "compare" || ev == "any") {
    return Proto(-32602, "stop_event 须为 swap | compare | any")
  }
  let max_frames = match jint(jget(args, "max_frames")) {
    Some(n) =>
      if n < 1 || n > CAP_FRAMES {
        return Proto(-32602, "max_frames 须为 1..20000")
      } else {
        n
      }
    None => 0
  }
  if bp == 0 && ev.length() == 0 && max_frames == 0 {
    // 都缺省 = 推进到终局
    match advance(e, CAP_FRAMES - e.frames.length(), 0, "") {
      Ok(a) => return Done(tool_text(run_to_body(e, a)))
      Err(m) => return Fail("推进失败：\{m}")
    }
  }
  let budget = if max_frames > 0 {
    max_frames
  } else {
    CAP_FRAMES - e.frames.length()
  }
  match advance(e, budget, bp, ev) {
    Ok(a) => {
      if phase_is_terminal(e.phase) {
        fetch_outputs(e)
      }
      Done(tool_text(run_to_body(e, a)))
    }
    Err(m) => return Fail("推进失败：\{m}")
  }
}

///|
fn run_to_body(e : Entry, a : Advance) -> Json {
  let o = ob()
    .s("session_id", e.id)
    .n("advanced", a.added)
    .n("frames_collected", e.frames.length())
    .s("stopped", e.stopped())
  if a.paused_at > 0 {
    ignore(o.n("paused_at", a.paused_at))
  }
  if a.event_step >= 0 {
    ignore(o.n("event_step", a.event_step))
  }
  if e.phase == PHASE_TRAPPED {
    ignore(o.j("run", run_summary_json(e)))
    ignore(o.j("outputs", outputs_json(e)))
  }
  if e.phase == PHASE_FINISHED {
    ignore(o.j("run", run_summary_json(e)))
    ignore(o.j("outputs", outputs_json(e)))
    ignore(
      o.s("next", "已终局——用 frames_query 回看 / render 出片"),
    )
  }
  o.done()
}

///|
fn Server::tool_step_next(self : Server, args : Json, now : Double) -> ToolOut {
  let e = match self.resolve(args, now) {
    Ok(v) => v
    Err(m) => return Fail(m)
  }
  if e.phase == PHASE_COMPILE_FAILED {
    return Fail("会话编译失败——无帧可推进")
  }
  let n = match jint(jget(args, "n")) {
    Some(k) =>
      if k < 1 || k > 100 {
        return Proto(-32602, "参数 n 须为 1..100")
      } else {
        k
      }
    None => 1
  }
  // 已终局：推进式收口（design §4.2——终局后 run_to/step_next 提示回看）
  if phase_is_terminal(e.phase) {
    return Done(
      tool_text(
        ob()
        .s("session_id", e.id)
        .n("advanced", 0)
        .n("keyframes", 0)
        .s("stopped", e.stopped())
        .s(
          "next", "已终局，不可回退推进——用 frames_query 回看 / render 出片",
        )
        .done(),
      ),
    )
  }
  let mut got = 0
  let mut raw = 0
  let keys : Array[Json] = []
  let mut prev : Frame? = if e.last_key >= 0 && e.last_key < e.frames.length() {
    Some(e.frames[e.last_key])
  } else {
    None
  }
  while got < n &&
        raw < 2000 &&
        !phase_is_terminal(e.phase) &&
        e.frames.length() < CAP_FRAMES {
    let before = e.frames.length()
    match advance(e, 1, 0, "") {
      Ok(_) => ()
      Err(m) => return Fail("推进失败：\{m}")
    }
    raw += e.frames.length() - before
    if e.frames.length() == before {
      break // 零推进（空转保护）
    }
    for k = before; k < e.frames.length(); k = k + 1 {
      let fr = e.frames[k]
      // 关键帧判据的聚焦集 = 两帧出现过的全部数组（step_next 无渲染聚焦语境）
      let names = union_array_names(prev, fr)
      if key_weight(prev, fr, false, names) > 0 {
        got += 1
        keys.push(frame_json_proj(fr, []))
        prev = Some(fr)
        e.last_key = k
        if got >= n {
          break
        }
      }
    }
  }
  Done(
    tool_text(
      ob()
      .s("session_id", e.id)
      .n("advanced", raw)
      .n("keyframes", got)
      .a("frames", keys)
      .n("frames_collected", e.frames.length())
      .s("stopped", e.stopped())
      .done(),
    ),
  )
}

///|
fn union_array_names(a : Frame?, b : Frame) -> Array[String] {
  let names : Array[String] = []
  match a {
    Some(x) =>
      for name, _ in x.r {
        if !names.contains(name) {
          names.push(name)
        }
      }
    None => ()
  }
  for name, _ in b.r {
    if !names.contains(name) {
      names.push(name)
    }
  }
  names
}

///|
/// 渲染参数校验 + 壳层钩子调用（animate / render 共用；ms_engine = 引擎侧
/// 已耗时，由调用方传入）。
fn Server::render_entry(
  self : Server,
  e : Entry,
  args : Json,
  ms_engine : Int32,
) -> ToolOut {
  let mode = jstr_or(jget(args, "mode"), "static")
  if !(mode == "static" || mode == "interactive") {
    return Proto(-32602, "参数 mode 须为 \"static\" 或 \"interactive\"")
  }
  let theme = jstr_or(jget(args, "theme"), "auto")
  if !(theme == "auto" || theme == "light" || theme == "dark") {
    return Proto(-32602, "参数 theme 须为 auto | light | dark")
  }
  let budget = match jint(jget(args, "budget")) {
    Some(b) =>
      if b < 16 || b > 4000 {
        return Proto(-32602, "参数 budget 须为 16..4000")
      } else {
        b
      }
    None => 400
  }
  // 惰性全采（仅 Opened——推进中〔Started/paused〕的会话渲染当前缓冲，
  // 不替 agent 做推进决策；终局渲染完整缓冲）
  if e.phase == PHASE_OPENED {
    match collect_all(e) {
      Ok(_) => ()
      Err(m) => return Fail(m)
    }
  }
  let total = e.frames.length()
  let from = max_int(0, jint_or(jget(args, "from"), 0))
  let to = min_int(
    total,
    match jint(jget(args, "to")) {
      Some(t) => t
      None => total
    },
  )
  if from >= to && total > 0 && from >= total {
    return Proto(-32602, "参数 from/to 区间越界（frames \{total} 帧）")
  }
  let slice : Array[Frame] = []
  for i = from; i < to; i = i + 1 {
    slice.push(e.frames[i])
  }
  let focus = pick_focus_arrays(slice, jstr_arr(jget(args, "focus")))
  // 关键帧恒算（interactive 亦算——壳层无 wasm 回落 static 时「回落即用」，
  // 消「回落成无帧空壳」的双源分叉；真 interactive 时壳层不嵌帧）
  let (idx, thinned) = if slice.length() > 0 {
    extract_keyframes(slice, focus, budget)
  } else {
    ([], false)
  }
  let frames_json : Array[Json] = []
  for i in idx {
    frames_json.push(frame_json_full(slice[i], focus))
  }
  // 警告（v1 口径：编译成功带 warning 级诊断；采集提前停注明）
  let warnings : Array[String] = []
  for d in jarr(jget(e.compile_result, "diagnostics")) {
    let sev = jint_or(jget(d, "severity"), 0)
    if sev > 0 {
      let code = jstr_or(jget(d, "code"), "")
      if code.has_prefix("W") {
        warnings.push(
          "\{code} \{jstr_or(jget(d, "filename"), "main.c")}:\{jint_or(jget(d, "line"), 0)}:\{jint_or(jget(d, "column"), 0)} \{jstr_or(jget(d, "message"), "")}",
        )
      }
    }
  }
  if e.phase == PHASE_COMPILE_FAILED {
    for d in jarr(jget(e.compile_result, "diagnostics")) {
      let code = jstr_or(jget(d, "code"), "")
      warnings.push(
        "\{code} \{jstr_or(jget(d, "filename"), "main.c")}:\{jint_or(jget(d, "line"), 0)}:\{jint_or(jget(d, "column"), 0)} \{jstr_or(jget(d, "message"), "")}\{match jstr(jget(d, "fix_suggestion")) { Some(f) => " — 建议：" + f; None => "" }}",
      )
    }
  }
  let stopped = e.stopped()
  if e.phase == PHASE_WAITING_INPUT {
    warnings.push("采集提前停止：waiting_input（stdin 交互程序）")
  }
  if e.phase == PHASE_TRAPPED {
    warnings.push("采集提前停止：\{stopped}")
  }
  if e.phase == PHASE_STARTED && e.paused_at > 0 {
    warnings.push(
      "会话仍在推进中（paused@\{e.paused_at}）——渲染的是当前缓冲 \{total} 帧，非全量",
    )
  }
  // 标题优先级：args.title > 会话 title > 算法名/缺省
  let algo = first_algo(e)
  let algo_name = jstr_or(jget(algo, "name"), "")
  let title = match jstr(jget(args, "title")) {
    Some(t) => t
    None =>
      if e.title.length() > 0 {
        e.title
      } else if algo_name.length() > 0 {
        "\{jstr_or(jget(algo, "display_name"), algo_name)} · vitro 动画"
      } else {
        "C 代码执行动画 · vitro"
      }
  }
  let data = ob()
    .s("mode", mode)
    .s("title", title)
    .s("source", e.source)
    .a("frames", frames_json)
    .sa("focus", focus)
    .j("algo", algo)
    .j("run", run_summary_json(e))
    .j("outputs", outputs_json(e))
    .j("diagnostics", jget(e.compile_result, "diagnostics"))
    .b("compile_ok", e.phase != PHASE_COMPILE_FAILED)
    .sa("warnings", warnings)
    .s("theme", theme)
    .b("audio", jbool_or(jget(args, "audio_description"), false))
    .b("thinned", thinned)
    .n("raw_count", slice.length())
    .j("versions", engine_versions())
    .s("out_dir", jstr_or(jget(args, "out_dir"), ""))
    .b("preview_png", jbool_or(jget(args, "preview_png"), true))
    .s("slug", if algo_name.length() > 0 { algo_name } else { "program" })
    .done()
  let t0 = self.now()
  let r = (self.host.render)(data)
  let ms_render = (self.now() - t0).to_int()
  if !jbool_or(jget(r, "ok"), false) {
    return Fail(
      "渲染失败：\{jstr_or(jget(r, "error"), "壳层渲染钩子异常")}",
    )
  }
  for w in jstr_arr(jget(r, "warnings")) {
    warnings.push(w)
  }
  // 响应元数据取壳层实测值（回落时 mode_used=static / frame_count=实际嵌帧数）
  let mode_used = jstr_or(jget(r, "mode_used"), mode)
  let frame_count = jint_or(jget(r, "frame_count"), idx.length())
  let body = ob()
    .b("ok", e.phase != PHASE_COMPILE_FAILED)
    .s("html_path", jstr_or(jget(r, "html_path"), ""))
    .s("mode", mode_used)
    .n("frame_count", frame_count)
    .n("raw_step_count", slice.length())
    .b("thinned", if mode_used == "static" { thinned } else { false })
    .d("duration_estimate_s", frame_count.to_double() * 0.2)
    .j("algorithm_detected", algo)
    .sa("arrays_focused", focus)
    .j("outputs", outputs_json(e))
    .j("run", run_summary_json(e))
    .sa("warnings", warnings)
    .n("size_bytes", jint_or(jget(r, "size_bytes"), 0))
    .j("engine", engine_versions())
    .j("ms", ob().n("engine", ms_engine).n("render", ms_render).done())
    .s(
      "hint", "用 DSH 的 present 工具把 html_path 交付给用户（deliverables 卡片点开即播）；iframe 嵌入加 #play 后缀自动播放",
    )
  match jstr(jget(r, "preview_png_path")) {
    Some(p) => ignore(body.s("preview_png_path", p))
    None => ()
  }
  match jstr(jget(r, "preview_png_b64")) {
    Some(b64) => Done(tool_text_image(body.done(), b64))
    None => Done(tool_text(body.done()))
  }
}

///|
fn Server::tool_render(self : Server, args : Json, now : Double) -> ToolOut {
  let e = match self.resolve(args, now) {
    Ok(v) => v
    Err(m) => return Fail(m)
  }
  self.render_entry(e, args, 0)
}

///|
fn Server::tool_session_close(
  self : Server,
  args : Json,
  now : Double,
) -> ToolOut {
  ignore(now)
  let id = match jstr(jget(args, "session_id")) {
    Some(s) => s
    None =>
      match pool_most_recent(self.entries) {
        Some(s) => s
        None =>
          return Fail("无活跃会话可关（sessions() 可查列表）")
      }
  }
  if !self.entries.contains(id) {
    return Fail("会话 \{id} 不存在或已过期")
  }
  self.entries.remove(id)
  match true {
    true =>
      Done(
        tool_text(
          ob()
          .s("closed", id)
          .n("remaining", self.entries.length())
          .s(
            "next",
            if self.entries.length() == 0 {
              "已无活跃会话——L1 工具即将收回（tools/list_changed）"
            } else {
              "其余会话仍在（工具集不变）"
            },
          )
          .done(),
        ),
      )
    false => Fail("会话 \{id} 不存在或已过期")
  }
}
