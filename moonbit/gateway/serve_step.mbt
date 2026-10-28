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
// 分叉登记：①~~trap 帧的 root_cause_hint 恒 null~~ **已销案（M14，S8
// analysis 批 2026-10-03）**：trace_analyzer 六分析器照搬入 time_travel，
// run_batch Trap 分支装配——装配结构同形、**输出面分叉**（oracle
// engine.rs:198 restore 先以快照覆写 error ⇒ :208 取到空串 ⇒ 六臂全不
// 命中、hint 恒 null——oracle 取值时序缺陷，随退役收敛；本侧真 hint）；
// ②两层层号预算：engine 预算消费会话 config.max_steps（2026-10-04
// Blocker 1 修正——原 new() 恒 100_000 致 config/--max-steps 对引擎无效 +
// 错配时假 finished），vm 内建 max_steps（config.set 应用）同源——两层
// 一致，到顶走 vm 层步数超限 trap 真语义。

///|
/// 源码行供给（SourceLineProvider 适配器——Session.source_line_at 的
/// P0-4 多文件安全口，L9〔现 L8〕trait 依赖反转的编排层实现）。
priv struct SessionLines {
  s : @session.Session
}

///|
impl @time_travel.SourceLineProvider for SessionLines with fn source_line_at(
  self : SessionLines,
  line : Int32,
) -> String? {
  self.s.source_line_at(line)
}

///|
/// #90（2026-10-17）：帧文件归属适配器——Session.source_file_at 直通
/// （file_ranges 映射在 session 侧，编排层只做依赖反转接线）。
impl @time_travel.SourceLineProvider for SessionLines with fn source_file_at(
  self : SessionLines,
  line : Int32,
) -> String? {
  self.s.source_file_at(line)
}

///|
/// StepPayload → Json（Rust serde 序 14 字段——显式 emitter 纪律，字段
/// 序/Option 形态逐位对齐 unified/types.rs:16-31）。
/// v0.2 首批（#90，2026-10-17）：code_file 插在 code_line 之后（语义
/// 相邻——「这行属于哪个文件」紧跟「这行是哪行」）；additive-only，
/// v0.1 既有 14 键名/序不动。null 形态 = JSON null（结构性无映射的
/// 防御态——实测见 #90：单文件编译恒给文件名）。
fn step_payload_json(p : @protocol.StepPayload) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("step_index", Json(p.step_index))
  m.set("code_line", Json(p.code_line))
  m.set(
    "code_file",
    match p.code_file {
      Some(f) => Json(f)
      None => Json::null()
    },
  )
  m.set("func_name", Json(p.func_name))
  m.set("semantic_label", Json(p.semantic_label))
  // #231（2026-10-27）：受控词汇 id 同帧下发（classify 单源；空串=无标签）
  m.set("semantic_label_id", Json(p.semantic_label_id))
  m.set(
    "algorithm_step",
    match p.algorithm_step {
      Some(a) => {
        let am : Map[String, Json] = Map([])
        am.set("algorithm_name", Json(a.algorithm_name))
        am.set("display_name", Json(a.display_name))
        am.set("phase", Json(a.phase))
        am.set("description", Json(a.description))
        Json::object(am)
      }
      None => Json::null()
    },
  )
  let lvars : Array[Json] = []
  for v in p.local_vars {
    let vm_ : Map[String, Json] = Map([])
    vm_.set("name", Json(v.name))
    vm_.set("addr", Json::number(v.addr.to_double()))
    vm_.set("is_local", Json(v.is_local))
    vm_.set("ty_name", Json(v.ty_name))
    vm_.set("value", Json(v.value))
    lvars.push(Json::object(vm_))
  }
  m.set("local_vars", Json::array(lvars))
  let cs : Array[Json] = []
  for f in p.call_stack {
    let fm : Map[String, Json] = Map([])
    fm.set("func_name", Json(f.func_name))
    fm.set("return_line", Json(f.return_line))
    cs.push(Json::object(fm))
  }
  m.set("call_stack", Json::array(cs))
  let ves : Array[Json] = []
  for v in p.vis_events {
    let em : Map[String, Json] = Map([])
    em.set("ty", Json(v.ty))
    em.set("line", Json(v.line))
    em.set("extra0", Json(v.extra0))
    em.set("extra1", Json(v.extra1))
    em.set("extra2", Json(v.extra2))
    em.set("context", Json(v.context))
    ves.push(Json::object(em))
  }
  m.set("vis_events", Json::array(ves))
  m.set("heatmap_line", Json(p.heatmap_line))
  // serde u64 → number（core UInt64::to_json 出字符串——分叉修正；域内
  // 计数 ≤ 步数 < 2^31，to_int 无损〔超界域不可达，登记〕）
  m.set("heatmap_count", Json::number(p.heatmap_count.to_double()))
  let accs : Array[Json] = []
  for a in p.accessed_vars {
    let am : Map[String, Json] = Map([])
    am.set("name", Json(a.name))
    am.set("access_type", Json(a.access_type))
    accs.push(Json::object(am))
  }
  m.set("accessed_vars", Json::array(accs))
  let arrs : Array[Json] = []
  for a in p.array_snapshots {
    let am : Map[String, Json] = Map([])
    am.set("name", Json(a.name))
    am.set("element_ty", Json(a.element_ty))
    let elems : Array[Json] = []
    for e in a.elements {
      elems.push(Json(e))
    }
    am.set("elements", Json::array(elems))
    am.set("truncated", Json(a.truncated))
    arrs.push(Json::object(am))
  }
  m.set("array_snapshots", Json::array(arrs))
  let ptrs : Array[Json] = []
  for a in p.pointer_snapshots {
    let am : Map[String, Json] = Map([])
    am.set("name", Json(a.name))
    am.set("addr", Json::number(a.addr.to_double()))
    am.set("ty_name", Json(a.ty_name))
    am.set("target_addr", Json::number(a.target_addr.to_double()))
    am.set("target_name", Json(a.target_name))
    am.set("status", Json::string(a.status.to_json_text()))
    ptrs.push(Json::object(am))
  }
  m.set("pointer_snapshots", Json::array(ptrs))
  m.set(
    "root_cause_hint",
    match p.root_cause_hint {
      Some(h) => {
        let hm : Map[String, Json] = Map([])
        hm.set("category", Json(h.category))
        hm.set("one_liner", Json(h.one_liner))
        let rl : Array[Json] = []
        for l in h.related_lines {
          rl.push(Json(l))
        }
        hm.set("related_lines", Json::array(rl))
        hm.set("suggested_fix_kind", Json(h.suggested_fix_kind))
        hm.set(
          "suggested_fix_line",
          match h.suggested_fix_line {
            Some(l) => Json(l)
            None => Json::null()
          },
        )
        hm.set(
          "suggested_fix_desc",
          match h.suggested_fix_desc {
            Some(d) => Json(d)
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
  m.set("finished", Json(r.finished))
  m.set("trapped", Json(r.trapped))
  m.set("waiting_input", Json(r.waiting_input))
  m.set("paused", Json(r.paused))
  m.set("current_line", Json(r.current_line))
  m.set(
    "trap_message",
    match r.trap_message {
      Some(t) => Json(t)
      None => Json::null()
    },
  )
  m.set("cache_start_step", Json(r.cache_start_step))
  Json::object(m)
}

///|
/// SeekResult → Json（serde 序 3 字段）。
fn seek_result_json(r : @protocol.SeekResult) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("success", Json(r.success))
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
      Some(e) => Json(e)
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
  // engine 预算消费会话 config.max_steps（2026-10-04 性能实测 Blocker 1
  // 修正：原 UnifiedEngine::new() 恒默认 100_000——CLI/gateway 的
  // --max-steps/config.set 对 step 族引擎**无效**，且 engine<vm 错配时预算
  // 到顶返回假 finished（程序只跑 35% 却报正常结束）；消费 config 后两层
  // 同源、min(engine,vm) 错配形态消除——到顶走 vm 层步数超限 trap 真语义）
  let engine = @time_travel.UnifiedEngine::with_max_steps(s.config.max_steps)
  // #87 批：会话级检查点保留数应用（config.set max_checkpoints /
  // preset 档展开值——algo 档 200；build 时一次性带上）
  engine.checkpoints.set_max_checkpoints(s.config.max_checkpoints)
  // 算法检测产物注入（批四号接线——compile 通道产出 matches，引擎侧
  // AlgoInferCtx 消费；Rust 侧经 session AlgorithmContext::find_algorithm
  // 查询，本侧编排层直供同语义）
  engine.set_algorithm_matches(s.compile.algorithm_matches)
  // vm 五步重建（非 resume 形态——与 serve_execute_run 同源；输出清 +
  // vfs 重建 + 装载 + 动态堆起点 + 预设注入）
  s.vm.output.clear()
  s.vm.reset_vfs()
  // InputState 模式同步（issue #29 #5）：vm.new 默认 batch=true（空批
  // 模式——scanf 直达 EOF 不等待），会话默认 Interactive（oracle
  // InputMode #[default] Interactive 同款）——run 通道由 serve_run 的
  // 模式同步掩盖，step 流重建独缺此步 ⇒ waiting_input 永不上报
  s.vm.set_input(@host.InputState::new(s.vm.input.lines, s.runtime_batch))
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
  // issue #29 #4：vis 行随重建灌入（compile_pipeline.rs:364 同形——run/step
  // 两通道统一装配，demo 可视化侧栏的数据源）
  s.vm.setup_from_output(
    output,
    argc,
    s.runtime_argv,
    project_vis_lines(s.compile.algorithm_matches),
  )
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
  // 病 76（#71 P2，2026-10-16）：frames 参数实现化——api help 一直宣称
  // 「推进 N 步」（rules.json example {"frames":10}），实现恒 1 步
  //（_params 弃置——手写例与实现脱节）。缺省 1 = 旧调用方零变化；负值/
  // 零 fail loud（param_err——静默取 1 会把「想推进 100」的手滑变成单步
  // 慢放）。上限钳到 max_steps 配置（防一次推进吞满预算无诊断）。
  //
  // #89 稀疏出帧（2026-10-17，v0.2 供数批）：every = 采样步长——每 N 条
  // 指令采 1 帧（一次调用推进 N、发布 1；采样语义见 run_batch 头注）。
  // **frames 与 every 语义互斥**（N 步 N 帧 vs N 步 1 帧），双给 fail loud
  // （参数错误帧带 expected 形状）——不静默择一。
  //
  // 病 76 勘误（2026-10-17 审阅 P2-⑤，合并批连坐 every）：在场但非整数
  // （浮点/字符串/超 Int32 域）只有 0 哨兵的笼统「须为正整数」，与
  // config.set 的分类文案口径不一致——前置 #133 单源值域预检
  // （config_int_field_overflow：在场判断 + 浮点/字符串/超域分类文案，
  // frames/every 双键同款）。下方 unwrap_or(0) 哨兵保留为第二道防线
  // （预检已拦截的前提下理论不可达——防御纵深非冗余裁决）。
  match config_int_field_overflow(params, "frames", 2147483647) {
    Err(msg) =>
      return (
        serve_param_err(
          id,
          "step.next 的 params.frames 须为正整数：\{msg}",
          "frames:int>=1",
        ).stringify(),
        false,
      )
    Ok(_) => ()
  }
  match config_int_field_overflow(params, "every", 2147483647) {
    Err(msg) =>
      return (
        serve_param_err(
          id,
          "step.next 的 params.every 须为 1..100000 的整数（采样步长）：\{msg}",
          "every:int in [1,100000]",
        ).stringify(),
        false,
      )
    Ok(_) => ()
  }
  let frames_json = json_field(params, "frames")
  let every_json = json_field(params, "every")
  // 缺省（键缺省/null）取 1；存在且非整数 → 0 哨兵（0 同时落在下方
  // 正数校验的非法面，类型错与越界共用同一条 fail loud 路径）
  let frames : Int32 = match frames_json {
    Null => 1
    _ => frames_json.as_int().unwrap_or(0)
  }
  let every : Int32 = match every_json {
    Null => 1
    _ => every_json.as_int().unwrap_or(0)
  }
  if frames <= 0 {
    return (
      serve_param_err(
        id, "step.next 的 params.frames 须为正整数", "frames:int>=1",
      ).stringify(),
      false,
    )
  }
  if every <= 0 || every > 100000 {
    return (
      serve_param_err(
        id, "step.next 的 params.every 须为 1..100000 的整数（采样步长）",
        "every:int in [1,100000]",
      ).stringify(),
      false,
    )
  }
  if frames > 1 && every > 1 {
    return (
      serve_param_err(
        id, "step.next 的 params.frames 与 every 互斥（frames=N 步 N 帧；every=N 步 1 帧）",
        "frames:int>=1 XOR every:int in [1,100000]",
      ).stringify(),
      false,
    )
  }
  let advance = if every > 1 { every } else { frames }
  let stride = if every > 1 { every } else { 1 }
  let budget = s.config.max_steps
  let n = if advance > budget { budget } else { advance }
  let outcome = engine.run_batch(s.vm, SessionLines::{ s, }, n, every=stride)
  guard outcome is Ok(result) else {
    guard outcome is Err(msg) else { abort("unreachable") }
    return (serve_err(id, "state", msg).stringify(), false)
  }
  // 一帧发布缓冲（Rust `session_api.rs:678-721` 同位；**有意偏离 oracle**：
  // oracle 的 flushed = is_empty||finished **不含 trapped**、trap 分支只置
  // trapped 不置 finished——trap 帧同样永不发布，属 oracle 同病。本侧
  // issue #35 修正（2026-10-09）补 `||result.trapped` 主动纠偏，非照搬——
  // trap 是终态，trap 批必须连同缓冲帧一起冲刷发布。旧判定只认
  // is_empty||finished，trap 批（payloads=[trap 帧]）走 else 把 trap 帧
  // 吞进 unified_pending，而消费方见 trapped=true 即停、无人再调
  // step.next 冲刷——**trap 帧（含已装配的 root_cause_hint）永远发布不
  // 出去**（demo 死因卡恒空、CLI 端到端 hint 恒 null 的真断点）。安全性：
  // trap 后再调 step.next 走 engine 的 is_trapped 守卫返空 payload，不双发）。
  let flushed = result.payloads.is_empty() || result.finished || result.trapped
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
    guard curr is Some(c) else {
      abort("unreachable：非 flushed 必有一帧")
    }
    // §7.3 append 语义：pending 前插发布位；curr 移入缓冲
    //（#225 审阅 P2-1 定谳：批内帧的行末清标注由 FrameWindow.push_batch
    // 两段去重单源保证，serve 不重复；serve 只管自己持有的跨批 pending
    // ——其行末性参照**批首帧**（pop 后 payloads[0] 是 pending 在发布流
    // 中的真实后继）。旧判据用批尾 curr，frames>1 时批尾与 pending 中隔
    // 整批帧、同行性错位——跨批边界的行中间 pending 帧带标注漏出（行末
    // 不变量锚 frames=50 批形态证红；probe frames=300 恰未跨段复现，
    // 变异实验 + 锚双证据定谳）
    let mut to_publish = pending
    if result.payloads.length() > 0 &&
      result.payloads[0].code_line == to_publish.code_line {
      to_publish = { ..to_publish, algorithm_step: None, }
    }
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
  m.set("cache_start_step", Json(engine.frames.start_step()))
  m.set("max_collected_step", Json(engine.max_collected_step()))
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
      serve_param_err(id, "seek 需要 params.step:int", "step:int").stringify(),
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
  let lines : Array[Int32] = []
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
  // 病 7 修复（#47，2026-10-09）：回显从生效集读回（vm Set 视图——过滤/
  // 去重后），不再回显请求原始数组（旧形态 [4,-2,7] 里 -2 未生效也回显，
  // 与实际断点不一致——协议面撒谎，demo 断点 UI 显示错）。
  let arr : Array[Json] = []
  for l in s.vm.breakpoints_sorted() {
    arr.push(Json(l))
  }
  let m : Map[String, Json] = Map([])
  m.set("lines", Json::array(arr))
  (serve_ok(id, Json::object(m)).stringify(), false)
}
