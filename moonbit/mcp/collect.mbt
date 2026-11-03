// 采集层：两条采集路径共享同一帧缓冲（design.md §4.2）——惰性全采
// （frames_summary / frames_query / annotations / render 首次触发）与推进式
// （run_to / step_next）。引擎序列：run（概要）→ step.begin → step.next×N。
// 约束如实：实例终局后不可回退推进（回看走缓冲）；采集上限 CAP_FRAMES。
// 断点语义（vm/exec_debug.mbt StepEvent 臂）：命中置 paused，unpause 后从
// 下一条指令续跑——同行重设断点要到下次进入该行才再触发；breakpoints.set
// 空集 = 两层 unpause（serve_breakpoints_set_frame）。

///|
/// 一次 step.next 批量推进的帧数上限（1126 帧 bubble ≈ 5 次往返）。
const CHUNK : Int32 = 256

///|
priv struct Advance {
  added : Int32
  paused_at : Int32
  /// stop_event 命中帧号（-1 = 未命中）
  event_step : Int32
}

///|
/// Opened → Started：run（概要进 run_result）+ step.begin。
fn ensure_started(e : Entry) -> Result[Unit, String] {
  match e.phase {
    PHASE_OPENED => {
      let rp = if e.argv.length() > 0 {
        ob().sa("argv", e.argv).done()
      } else {
        Json::object(Map([]))
      }
      let r = match entry_call(e, "run", rp) {
        Ok(v) => v
        Err(m) => return Err(m)
      }
      e.run_result = r
      match entry_call0(e, "step.begin") {
        Ok(_) => ()
        Err(m) => return Err(m)
      }
      e.phase = PHASE_STARTED
      Ok(())
    }
    PHASE_COMPILE_FAILED =>
      Err(
        "会话编译失败——无帧可采（看 session_open 返回的 diagnostics，修源后重新 session_open）",
      )
    _ => Ok(())
  }
}

///|
/// 推进：最多 max_raw 原始帧；breakpoint>0 = 到该行暂停；stop_event 非空
/// （swap/compare/any）= 到首个此类可视事件帧停（逐帧精确推进）。
fn advance(
  e : Entry,
  max_raw : Int32,
  breakpoint : Int32,
  stop_event : String,
) -> Result[Advance, String] {
  match ensure_started(e) {
    Ok(_) => ()
    Err(m) => return Err(m)
  }
  if phase_is_terminal(e.phase) {
    return Ok({ added: 0, paused_at: 0, event_step: -1, })
  }
  // 先清空（两层 unpause + 旧断点作废），再按需设新断点
  match entry_call(e, "breakpoints.set", ob().a("lines", []).done()) {
    Ok(_) => ()
    Err(m) => return Err(m)
  }
  e.paused_at = 0
  if breakpoint > 0 {
    match
      entry_call(
        e,
        "breakpoints.set",
        ob().j("lines", jints([breakpoint])).done(),
      ) {
      Ok(_) => ()
      Err(m) => return Err(m)
    }
  }
  let exact = stop_event.length() > 0
  let mut added = 0
  let mut empties = 0
  let mut paused_at = 0
  let mut event_step = -1
  while added < max_raw && e.frames.length() < CAP_FRAMES {
    let n = if exact {
      1
    } else {
      min_int(CHUNK, min_int(max_raw - added, CAP_FRAMES - e.frames.length()))
    }
    let r = match entry_call(e, "step.next", ob().n("frames", n).done()) {
      Ok(v) => v
      Err(m) => return Err(m)
    }
    let payloads = jarr(jget(r, "payloads"))
    let mut hit = false
    for p in payloads {
      let fr = frame_of_payload(p)
      e.frames.push(fr)
      added += 1
      if exact && event_step < 0 {
        for ev in fr.e {
          let k = vis_kind(ev.ty)
          if stop_event == "any" || stop_event == k {
            event_step = fr.i
            paused_at = fr.l
            hit = true
            break
          }
        }
      }
    }
    empties = if payloads.length() == 0 { empties + 1 } else { 0 }
    if jbool_or(jget(r, "finished"), false) {
      e.phase = PHASE_FINISHED
      break
    }
    if jbool_or(jget(r, "trapped"), false) {
      e.phase = PHASE_TRAPPED
      e.trap_message = jstr_or(jget(r, "trap_message"), "")
      break
    }
    if jbool_or(jget(r, "waiting_input"), false) {
      e.phase = PHASE_WAITING_INPUT
      break
    }
    if jbool_or(jget(r, "paused"), false) {
      paused_at = jint_or(jget(r, "current_line"), breakpoint)
      break
    }
    if hit {
      break
    }
    // 滞后一帧语义：首调空批正常；连续 3 空批且未终局 = 不再空转
    if empties >= 3 {
      break
    }
  }
  if e.frames.length() >= CAP_FRAMES && !phase_is_terminal(e.phase) {
    e.phase = PHASE_CAPPED
  }
  e.paused_at = paused_at
  // 收尾副作用单点（PR #457 审阅 P1-1）：终态即回读输出——此前 fetch 只挂在
  // tool_run_to 的显式参数分支与 collect_all，全缺省提前 return 与 step_next
  // 推到终局的两条路径永久漏采（锚样本全显式参数，掩盖面）
  if phase_is_terminal(e.phase) {
    fetch_outputs(e)
  }
  Ok({ added, paused_at, event_step, })
}

///|
/// 惰性全采：推进到终局或上限（已终局/已采满则空操作）。
fn collect_all(e : Entry) -> Result[Unit, String] {
  if e.phase == PHASE_COMPILE_FAILED {
    return Err(
      "会话编译失败——无帧可采（看 session_open 返回的 diagnostics）",
    )
  }
  let mut guard_n = 0
  while !phase_is_terminal(e.phase) && guard_n < 512 {
    guard_n += 1
    let before = e.frames.length()
    match advance(e, CAP_FRAMES - e.frames.length(), 0, "") {
      Ok(_) => ()
      Err(m) => return Err(m)
    }
    if e.frames.length() == before && !phase_is_terminal(e.phase) {
      // 零推进且未终局（空转保护）——按无进展收口
      break
    }
  }
  fetch_outputs(e)
  Ok(())
}

///|
/// 输出通道回读（终局后一次；未终局也可读当前已产出）。
fn fetch_outputs(e : Entry) -> Unit {
  if e.phase == PHASE_COMPILE_FAILED || e.phase == PHASE_OPENED {
    return
  }
  e.stdout = read_output(e, "stdout")
  e.stderr = read_output(e, "stderr")
}

///|
fn outputs_json(e : Entry) -> Json {
  ob().s("stdout", e.stdout).s("stderr", e.stderr).done()
}

///|
/// run 概要投影（v1 animate.run 三字段 + trap 信息）。
fn run_summary_json(e : Entry) -> Json {
  match e.run_result {
    Object(_) as r =>
      ob()
      .s("status", jstr_or(jget(r, "status"), ""))
      .j("return_value", jget(r, "return_value"))
      .n("steps_executed", jint_or(jget(r, "steps_executed"), 0))
      .s("trap", jstr_or(jget(r, "trap"), ""))
      .done()
    _ => Json::null()
  }
}
