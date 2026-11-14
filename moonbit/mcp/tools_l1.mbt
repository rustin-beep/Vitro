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
  // PR #457 审阅 P3：显式 to < from fail loud（旧形态静默空页 + has_more 假真）
  match jint(jget(args, "to")) {
    Some(t) =>
      if t < from {
        return Proto(
          -32602, "参数 to 须 >= from（区间左闭右开：[from, to)）",
        )
      }
    None => ()
  }
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
  // PR #457 审阅 v2 P2-1：to 与 start+limit 双上限取小——显式区间不得旁路
  // 「每页 ≤50」契约（修前 to 优先：{to:超界} 一次吐全量、{to,limit} 并存
  // 时 limit 被无视）
  let end = min_int(
    match jint(jget(args, "to")) {
      Some(t) => min_int(t, start + limit)
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
    Ok(a) => Done(tool_text(run_to_body(e, a)))
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
/// 解析 render/animate 的 `viz` 参数（多行 `series …` 声明；缺省/空白 = 无）。
/// 文法单源在 @view（与课源 vitri-viz 同形），本包只做「非空却零声明」兜底。
fn parse_viz_arg(args : Json) -> Result[Array[@view.SeriesDecl], String] {
  let text = jstr_or(jget(args, "viz"), "")
  if text.trim().to_owned() == "" {
    return Ok([])
  }
  match @view.parse_series_decl_block(text) {
    Err(m) => Err(m)
    Ok(ds) =>
      if ds.length() == 0 {
        Err("文本非空但无有效声明行（只有空行/注释？）")
      } else {
        Ok(ds)
      }
  }
}

///|
/// 声明序列必须进 focus（否则帧投影里没有数组数据、宿主画不出来）：
/// 显式 focus 在前追加缺项；自动模式以声明序打底、再按频次补到 4 条。
fn focus_with_decls(
  auto : Array[String],
  explicit : Array[String],
  decls : Array[@view.SeriesDecl],
) -> Array[String] {
  let out : Array[String] = []
  if explicit.length() > 0 {
    for n in auto {
      out.push(n)
    }
    for d in decls {
      for n in d.series {
        if !out.contains(n) {
          out.push(n)
        }
      }
    }
    return out
  }
  for d in decls {
    for n in d.series {
      if !out.contains(n) {
        out.push(n)
      }
    }
  }
  for n in auto {
    if out.length() < 4 && !out.contains(n) {
      out.push(n)
    }
  }
  out
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
  if !theme_values().contains(theme) {
    return Proto(
      -32602, "参数 theme 须为 auto | light | dark 或 StylePack 主题 id（ice/rose/soft/paper/blueprint）",
    )
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
  // PR #457 审阅 P3：显式 to <= from fail loud（旧形态静默 0 帧）
  match jint(jget(args, "to")) {
    Some(t) =>
      if t <= from {
        return Proto(
          -32602, "参数 to 须大于 from（渲染区间左闭右开：[from, to)；不传 to = 到末帧）",
        )
      }
    None => ()
  }
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
  let decls = match parse_viz_arg(args) {
    Ok(d) => d
    Err(m) => return Proto(-32602, "参数 viz 无法解析：\{m}")
  }
  let explicit_focus = jstr_arr(jget(args, "focus"))
  let auto_focus = pick_focus_arrays(slice, explicit_focus)
  let focus = if decls.length() == 0 {
    auto_focus
  } else {
    focus_with_decls(auto_focus, explicit_focus, decls)
  }
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
  for d in decls {
    if @view.projector(d.projector) is None {
      warnings.push(
        "viz: 未知投影器 \{d.projector}（该声明在产物中显示错误面板）",
      )
    }
  }
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
    .j("doc", @view.doc_value(decls))
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
    // PR #457 审阅 v2 P3-②：ok 表「产物已落盘」（渲染真失败上方已走 Fail）
    // ——编译失败的诊断卡同样是可用交付物；编译态另立 compile_ok（修前
    // ok:false 让按 ok 判断的 agent 丢弃已落盘的诊断卡）
    .b("ok", true)
    .b("compile_ok", e.phase != PHASE_COMPILE_FAILED)
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
}
