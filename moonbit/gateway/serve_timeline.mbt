// timeline.plan（TimelinePlan v0.1 批一，2026-11-15，refs #470）：只读帧区间
// → 动效计划。消费面 = 宿主（demo/interactive 后续批）与外部集成方；本方法
// 不碰 StepPayload 协议面（plan 是帧之上的派生视图，零会话态写入）。
//
// 输入：params.start / params.end（帧序号区间，左闭右开，缺省 0..窗尾——
// 与 payload.get 同区间语义）；会话须先 step.begin（帧窗在 UnifiedEngine）。
// 输出：TimelinePlan v0.1（{pv, steps[]}，steps 与区间内发布帧零基同构）。
// 单源：plan 生成器 = vitro/engine/timeline（L0），本方法只做 DTO 适配。

///|
/// StepPayload → 最小帧视图（timeline 生成器的输入契约；不传 mcp Frame 类型）。
fn timeline_view_of_payload(p : @protocol.StepPayload) -> @timeline.FrameView {
  let events : Array[@timeline.FrameEvent] = []
  for v in p.vis_events {
    events.push({
      ty: v.ty,
      e0: v.extra0,
      e1: v.extra1,
      e2: v.extra2,
      context: v.context,
    })
  }
  let arrays : Array[(String, Int32)] = []
  for a in p.array_snapshots {
    arrays.push((a.name, a.elements.length()))
  }
  {
    code_line: p.code_line,
    func_name: p.func_name,
    semantic_label: p.semantic_label,
    vis_events: events,
    arrays,
  }
}

///|
/// timeline.plan 帧处理：区间校验（fail loud——新方法不留静默夹取面）+
/// payload.get 同源帧窗 + L0 生成器 + 对齐校验（步骤错位即 state 错）。
fn serve_timeline_plan_frame(
  s : @session.Session,
  id : Json,
  params : Json,
) -> (String, Bool) {
  guard s.unified is Some(engine) else {
    return (
      serve_err(
        id, "state", "统一模式会话未初始化：请先调用 vitro_step_begin",
      ).stringify(),
      false,
    )
  }
  let start = match json_field(params, "start") {
    Null => 0
    v =>
      match v.as_int() {
        Some(n) => n
        None =>
          return (
            serve_param_err(
              id, "timeline.plan 的 params.start 须为整数帧序号", "start:int>=0",
            ).stringify(),
            false,
          )
      }
  }
  let end = match json_field(params, "end") {
    Null => 2147483647
    v =>
      match v.as_int() {
        Some(n) => n
        None =>
          return (
            serve_param_err(
              id, "timeline.plan 的 params.end 须为整数帧序号", "end:int>=start",
            ).stringify(),
            false,
          )
      }
  }
  if start < 0 {
    return (
      serve_param_err(
        id,
        "timeline.plan 的 params.start 不能为负数：\{start}",
        "start:int>=0",
      ).stringify(),
      false,
    )
  }
  if end < start {
    return (
      serve_param_err(
        id,
        "timeline.plan 的 params.end 须 >= start（区间左闭右开：[start, end)；收到 start=\{start} end=\{end}）",
        "end:int>=start",
      ).stringify(),
      false,
    )
  }
  let payloads = engine.get_payloads(start, end)
  let views : Array[@timeline.FrameView] = []
  for p in payloads {
    views.push(timeline_view_of_payload(p))
  }
  let p : @timeline.Plan = @timeline.plan(views)
  match @timeline.validate(p, views.length()) {
    Ok(_) => ()
    Err(m) => return (serve_err(id, "state", m).stringify(), false)
  }
  (serve_ok(id, @timeline.plan_json(p)).stringify(), false)
}
