// S8 批一号接线批（2026-10-01）：serve step 族五方法——step.begin /
// step.next / payload.get / seek / breakpoints.set。编排本体 = time_travel
// 批一号三段-c 的 UnifiedEngine（run_batch/seek_to）；照搬源：
// native/src/bin/vitro_cli.rs serve 段五臂 + native/src/session_api.rs
// step_begin(646)/step_next(669)/payloads(850)/seek(862)/set_breakpoints(874)。
//
// **层位裁定（本批落定）**：time_travel 自 L9 降 L8（与 session/gateway
// 同层）——依赖面全 ≤L8（vm/memory/protocol/ast/bytecode/host/opcode），
// 语义 = 时间旅行**编排引擎**非教学智能（智能判据词汇已上提 protocol，
// 勘察 ⑤-5.7）；L9 留给 teaching/analysis/diagnostics 真智能域。gateway
// (L8) 消费 time_travel(L8) 同层合法（降层前 L8→L9 违反 §4 单向约束，
// step 族接线暴露的结构题）。
//
// 分叉登记：①trap 帧的 root_cause_hint 恒 null（TraceAnalyzer 随
// analysis 批——engine 侧同源登记）；②两层层号预算：engine.new() 默认
// 100_000（Rust step_begin 同款 new()），vm 内建 max_steps（config.set
// 应用）更小时 vm 层先 trap——行为受 min(engine, vm) 控制同 Rust。

///|
/// 源码行供给（SourceLineProvider 适配器——Session.source_line_at 的
/// P0-4 多文件安全口，L9〔现 L8〕trait 依赖反转的编排层实现）。
priv struct SessionLines {
  s : @session.Session
}

///|
impl @time_travel.SourceLineProvider for SessionLines with fn source_line_at(
  self : SessionLines,
  line : Int,
) -> String? {
  self.s.source_line_at(line)
}

///|
/// StepPayload → Json（Rust serde 序 14 字段——显式 emitter 纪律，字段
/// 序/Option 形态逐位对齐 unified/types.rs:16-31）。
fn step_payload_json(p : @protocol.StepPayload) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("step_index", p.step_index.to_json())
  m.set("code_line", p.code_line.to_json())
  m.set("func_name", p.func_name.to_json())
  m.set("semantic_label", p.semantic_label.to_json())
  m.set(
    "algorithm_step",
    match p.algorithm_step {
      Some(a) => {
        let am : Map[String, Json] = Map([])
        am.set("algorithm_name", a.algorithm_name.to_json())
        am.set("display_name", a.display_name.to_json())
        am.set("phase", a.phase.to_json())
        am.set("description", a.description.to_json())
        Json::object(am)
      }
      None => Json::null()
    },
  )
  let lvars : Array[Json] = []
  for v in p.local_vars {
    let vm_ : Map[String, Json] = Map([])
    vm_.set("name", v.name.to_json())
    vm_.set("addr", Json::number(v.addr.to_double()))
    vm_.set("is_local", v.is_local.to_json())
    vm_.set("ty_name", v.ty_name.to_json())
    vm_.set("value", v.value.to_json())
    lvars.push(Json::object(vm_))
  }
  m.set("local_vars", Json::array(lvars))
  let cs : Array[Json] = []
  for f in p.call_stack {
    let fm : Map[String, Json] = Map([])
    fm.set("func_name", f.func_name.to_json())
    fm.set("return_line", f.return_line.to_json())
    cs.push(Json::object(fm))
  }
  m.set("call_stack", Json::array(cs))
  let ves : Array[Json] = []
  for v in p.vis_events {
    let em : Map[String, Json] = Map([])
    em.set("ty", v.ty.to_json())
    em.set("line", v.line.to_json())
    em.set("extra0", v.extra0.to_json())
    em.set("extra1", v.extra1.to_json())
    em.set("extra2", v.extra2.to_json())
    em.set("context", v.context.to_json())
    ves.push(Json::object(em))
  }
  m.set("vis_events", Json::array(ves))
  m.set("heatmap_line", p.heatmap_line.to_json())
  // serde u64 → number（core UInt64::to_json 出字符串——分叉修正；域内
  // 计数 ≤ 步数 < 2^31，to_int 无损〔超界域不可达，登记〕）
  m.set("heatmap_count", Json::number(p.heatmap_count.to_double()))
  let accs : Array[Json] = []
  for a in p.accessed_vars {
    let am : Map[String, Json] = Map([])
    am.set("name", a.name.to_json())
    am.set("access_type", a.access_type.to_json())
    accs.push(Json::object(am))
  }
  m.set("accessed_vars", Json::array(accs))
  let arrs : Array[Json] = []
  for a in p.array_snapshots {
    let am : Map[String, Json] = Map([])
    am.set("name", a.name.to_json())
    am.set("element_ty", a.element_ty.to_json())
    let elems : Array[Json] = []
    for e in a.elements {
      elems.push(e.to_json())
    }
    am.set("elements", Json::array(elems))
    am.set("truncated", a.truncated.to_json())
    arrs.push(Json::object(am))
  }
  m.set("array_snapshots", Json::array(arrs))
  let ptrs : Array[Json] = []
  for a in p.pointer_snapshots {
    let am : Map[String, Json] = Map([])
    am.set("name", a.name.to_json())
    am.set("addr", Json::number(a.addr.to_double()))
    am.set("ty_name", a.ty_name.to_json())
    am.set("target_addr", Json::number(a.target_addr.to_double()))
    am.set("target_name", a.target_name.to_json())
    am.set("status", Json::string(a.status.to_json_text()))
    ptrs.push(Json::object(am))
  }
  m.set("pointer_snapshots", Json::array(ptrs))
  m.set(
    "root_cause_hint",
    match p.root_cause_hint {
      Some(h) => {
        let hm : Map[String, Json] = Map([])
        hm.set("category", h.category.to_json())
        hm.set("one_liner", h.one_liner.to_json())
        let rl : Array[Json] = []
        for l in h.related_lines {
          rl.push(l.to_json())
        }
        hm.set("related_lines", Json::array(rl))
        hm.set("suggested_fix_kind", h.suggested_fix_kind.to_json())
        hm.set(
          "suggested_fix_line",
          match h.suggested_fix_line {
            Some(l) => l.to_json()
            None => Json::null()
          },
        )
        hm.set(
          "suggested_fix_desc",
          match h.suggested_fix_desc {
            Some(d) => d.to_json()
            None => Json::null()
          },
        )
        Json::object(hm)
      }
      None => Json::null()
    },
  )
  Json::object(m)
}

///|
/// AutoStepResult → Json（serde 序 8 字段——unified/types.rs:137-147）。
fn auto_step_result_json(r : @protocol.AutoStepResult) -> Json {
  let payloads : Array[Json] = []
  for p in r.payloads {
    payloads.push(step_payload_json(p))
  }
  let m : Map[String, Json] = Map([])
  m.set("payloads", Json::array(payloads))
  m.set("finished", r.finished.to_json())
  m.set("trapped", r.trapped.to_json())
  m.set("waiting_input", r.waiting_input.to_json())
  m.set("paused", r.paused.to_json())
  m.set("current_line", r.current_line.to_json())
  m.set(
    "trap_message",
    match r.trap_message {
      Some(t) => t.to_json()
      None => Json::null()
    },
  )
  m.set("cache_start_step", r.cache_start_step.to_json())
  Json::object(m)
}

///|
/// SeekResult → Json（serde 序 3 字段）。
fn seek_result_json(r : @protocol.SeekResult) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("success", r.success.to_json())
  m.set(
    "payload",
    match r.payload {
      Some(p) => step_payload_json(p)
      None => Json::null()
    },
  )
  m.set(
    "error",
    match r.error {
      Some(e) => e.to_json()
      None => Json::null()
    },
  )
  Json::object(m)
}

///|
/// step.begin（session_api.rs:646 step_begin + vitro_cli.rs:862 臂照搬）：
/// 未编译 → state 错误帧（Rust -2 文案）；成功 = 清发布缓冲（U1#1 二审
/// P0-A：同会话二次运行不发旧程序滞留帧）+ 新建引擎 + vm 五步重建
/// （serve_execute_run 非 resume 段同款）+ 检查点 0（Rust step_begin
/// 显式 save(0)——run_batch 首循环的双保险）。
fn serve_step_begin_frame(
  s : @session.Session,
  id : Json,
  _params : Json,
) -> (String, Bool) {
  if !s.compile.compiled {
    return (
      serve_err(
        id, "state", "统一模式初始化失败（返回 -2）：会话需先编译成功",
      ).stringify(),
      false,
    )
  }
  s.unified_pending = None
  let engine = @time_travel.UnifiedEngine::new()
  // 算法检测产物注入（批四号接线——compile 通道产出 matches，引擎侧
  // AlgoInferCtx 消费；Rust 侧经 session AlgorithmContext::find_algorithm
  // 查询，本侧编排层直供同语义）
  engine.set_algorithm_matches(s.compile.algorithm_matches)
  // vm 五步重建（非 resume 形态——与 serve_execute_run 同源；输出清 +
  // vfs 重建 + 装载 + 动态堆起点 + 预设注入）
  s.vm.output.clear()
  s.vm.reset_vfs()
  let output = match s.compile.output {
    Some(o) => o
    None =>
      return (
        serve_err(
          id, "state", "统一模式初始化失败：编译产物缺失",
        ).stringify(),
        false,
      )
  }
  let argc = s.runtime_argv.length()
  s.vm.setup_from_output(output, argc, s.runtime_argv)
  s.vm.mem_map.set_heap_base(
    @bytecode.compute_heap_base(output.global_data_end, argc, s.runtime_argv),
  )
  ignore(
    s.vm.vfs.inject_preset_file(
      s.vm.mem_map,
      s.vm.memory,
      "test.txt",
      b"hello\nworld\n",
    ),
  )
  ignore(
    s.vm.vfs.inject_preset_file(
      s.vm.mem_map,
      s.vm.memory,
      "numbers.txt",
      b"1 2 3 4 5\n",
    ),
  )
  engine.checkpoints.save(0, s.vm)
  s.unified = Some(engine)
  let m : Map[String, Json] = Map([])
  m.set("ready", Json::boolean(true))
  m.set("max_collected_step", Json::number(-1))
  (serve_ok(id, Json::object(m)).stringify(), false)
}

///|
/// step.next（session_api.rs:669 + 一帧发布缓冲 U1#1 P0-1/R2 照搬）：
/// run_batch(batch=1)；**滞后一帧**语义——首调只建缓冲返回空 payloads
/// （R2：首调发布克隆 = 同步重复投递缺陷形态）；当前帧与上一帧同
/// code_line 时上一帧清标注（语句中间帧）；结束/无新帧冲刷缓冲。
fn serve_step_next_frame(
  s : @session.Session,
  id : Json,
  _params : Json,
) -> (String, Bool) {
  guard s.unified is Some(engine) else {
    return (
      serve_err(
        id, "state", "统一模式会话未初始化：请先调用 vitro_step_begin",
      ).stringify(),
      false,
    )
  }
  let outcome = engine.run_batch(s.vm, SessionLines::{ s, }, 1)
  guard outcome is Ok(result) else {
    guard outcome is Err(msg) else { abort("unreachable") }
    return (serve_err(id, "state", msg).stringify(), false)
  }
  // 一帧发布缓冲（Rust 语义逐分支照搬——注释链见 session_api.rs:678-721）
  let flushed = result.payloads.is_empty() || result.finished
  if flushed {
    // 程序结束/无新帧：冲刷缓存帧（与结束帧同行则它不是行末，清标注）
    guard s.unified_pending is Some(pending) else {
      s.unified_pending = None
      return (serve_ok(id, auto_step_result_json(result)).stringify(), false)
    }
    s.unified_pending = None
    let mut to_flush = pending
    if result.payloads.length() > 0 &&
      result.payloads[result.payloads.length() - 1].code_line ==
      to_flush.code_line {
      to_flush = { ..to_flush, algorithm_step: None, }
    }
    result.payloads.insert(0, to_flush)
  } else {
    let curr = result.payloads.pop()
    guard s.unified_pending is Some(pending) else {
      // 首调：curr 仅入缓冲、不发布（R2 修正语义）
      s.unified_pending = curr
      return (serve_ok(id, auto_step_result_json(result)).stringify(), false)
    }
    let mut to_publish = pending
    guard curr is Some(c) else {
      abort("unreachable：非 flushed 必有一帧")
    }
    if c.code_line == to_publish.code_line {
      to_publish = { ..to_publish, algorithm_step: None, }
    }
    // §7.3 append 语义：pending 前插发布位；curr 移入缓冲
    result.payloads.insert(0, to_publish)
    s.unified_pending = Some(c)
  }
  (serve_ok(id, auto_step_result_json(result)).stringify(), false)
}

///|
/// payload.get（session_api.rs:850 + vitro_cli.rs:877 臂）：[start, end)
/// 区间帧（窗口外静默裁剪）+ 窗口起点 + 已收集最大步。
fn serve_payload_get_frame(
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
  let start = match json_field(params, "start").as_int() {
    Some(v) => v
    None => 0
  }
  // Rust 缺省 i32::MAX（全量到窗尾）
  let end = match json_field(params, "end").as_int() {
    Some(v) => v
    None => 2147483647
  }
  let frames = engine.get_payloads(start, end)
  let arr : Array[Json] = []
  for p in frames {
    arr.push(step_payload_json(p))
  }
  let m : Map[String, Json] = Map([])
  m.set("payloads", Json::array(arr))
  m.set("cache_start_step", engine.frames.start_step().to_json())
  m.set("max_collected_step", engine.max_collected_step().to_json())
  (serve_ok(id, Json::object(m)).stringify(), false)
}

///|
/// seek（session_api.rs:862 + vitro_cli.rs:888 臂）：params.step 必填；
/// 窗口内直返 / 越窗检查点恢复 + 正向重放（协议 §4.2 五步）。
fn serve_seek_frame(
  s : @session.Session,
  id : Json,
  params : Json,
) -> (String, Bool) {
  guard json_field(params, "step").as_int() is Some(target) else {
    return (
      serve_err(id, "protocol", "seek 需要 params.step").stringify(),
      false,
    )
  }
  guard s.unified is Some(engine) else {
    return (
      serve_err(
        id, "state", "统一模式会话未初始化：请先调用 vitro_step_begin",
      ).stringify(),
      false,
    )
  }
  let result = engine.seek_to(target, s.vm, SessionLines::{ s, })
  (serve_ok(id, seek_result_json(result)).stringify(), false)
}

///|
/// breakpoints.set（session_api.rs:874 + vitro_cli.rs:900 臂）：先清后设
/// （非正行号过滤）；空断点 = 两层暂停恢复（vm 层 + 引擎层——S3 A2/A3
/// 口径：清空断点即恢复推进，serve 出口明示的恢复手段）。
fn serve_breakpoints_set_frame(
  s : @session.Session,
  id : Json,
  params : Json,
) -> (String, Bool) {
  let lines : Array[Int] = []
  match json_field(params, "lines") {
    Array(arr) =>
      for v in arr {
        match v.as_int() {
          Some(n) => lines.push(n)
          None => ()
        }
      }
    _ => ()
  }
  s.vm.clear_breakpoints()
  for l in lines {
    if l > 0 {
      s.vm.add_breakpoint(l)
    }
  }
  if lines.is_empty() {
    s.vm.unpause()
    match s.unified {
      Some(engine) => engine.unpause()
      None => ()
    }
  }
  let arr : Array[Json] = []
  for l in lines {
    arr.push(l.to_json())
  }
  let m : Map[String, Json] = Map([])
  m.set("lines", Json::array(arr))
  (serve_ok(id, Json::object(m)).stringify(), false)
}
