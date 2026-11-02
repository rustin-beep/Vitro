// desktop/app：vitro 引擎命令层（demo 前端的桌面通道后端）。
//
// 官方 app-owned 形态：顶层 @proton_contract.command（Application scope，
// JS 侧 op 名 = `app:<name>`）经 main.mbt `..commands()` 注册——对齐 proton
// isomorphic 模板「逻辑在 backend」的桌面做法：**编排归 native 端**，
// step.next 采帧循环在 native 进程内闭环（IPC 往返 = 整段一次，非每帧一次
// ——demo 浏览器形态里这段循环在 Web Worker 内闭环，消息形状不变）。
//
// 四命令与 demo/src/protocol/engine.worker.ts 的四个 op 一一对应（协议
// 序列逐条照抄该文件，不做协议面发明）：
//   vitro_versions ← boot（engine/protocol 版本对）
//   vitro_invoke   ← invoke（网关单口原样转发，错误帧不折叠）
//   vitro_collect  ← collect（reset→session.create→config.set→compile→run→
//                    step.begin→breakpoints.set→drain→pullOutputs 编排）
//   vitro_feed     ← feed（input.feed→step.begin→drain→pullOutputs）
// 响应 JSON 键名与 engine.worker.ts 的 CollectResult 契约逐字对齐
// （camelCase：compileOk/ppTrace/bpLines 由 demo 侧 IPC shim 负责映射）。

///|
suberror EngineError {
  Frame(message~ : String)
} derive(Debug)

///|
pub extend EngineError with Debug::{to_repr}

///|
struct VersionsReply {
  engine : String
  protocol : String
} derive(ToJson, FromJson)

///|
pub extend VersionsReply with ToJson::{to_json}

///|
pub extend VersionsReply with FromJson::{from_json}

///|
struct InvokeRequest {
  api : String
  params : Json?
} derive(ToJson, FromJson)

///|
pub extend InvokeRequest with ToJson::{to_json}

///|
pub extend InvokeRequest with FromJson::{from_json}

///|
struct CompileFile {
  filename : String
  source : String
} derive(ToJson, FromJson)

///|
pub extend CompileFile with ToJson::{to_json}

///|
pub extend CompileFile with FromJson::{from_json}

///|
struct CollectRequest {
  source : String?
  cap : Int32?
  bp_lines : Array[Int32]?
  files : Array[CompileFile]?
  cfg : Json?
  argv : Array[String]?
} derive(ToJson, FromJson)

///|
pub extend CollectRequest with ToJson::{to_json}

///|
pub extend CollectRequest with FromJson::{from_json}

///|
struct FeedRequest {
  text : String
  cap : Int32?
} derive(ToJson, FromJson)

///|
pub extend FeedRequest with ToJson::{to_json}

///|
pub extend FeedRequest with FromJson::{from_json}

///|
let versions_command : @proton_contract.Command[
  @proton_contract.EmptyRequest,
  VersionsReply,
] = @proton_contract.command("vitro_versions")

///|
let invoke_command : @proton_contract.Command[InvokeRequest, Json] = @proton_contract.command(
  "vitro_invoke",
)

///|
let collect_command : @proton_contract.Command[CollectRequest, Json] = @proton_contract.command(
  "vitro_collect",
)

///|
let feed_command : @proton_contract.Command[FeedRequest, Json] = @proton_contract.command(
  "vitro_feed",
)

///|
pub fn register_engine_commands(
  registrar : @proton.CommandRegistrar,
) -> Unit raise {
  registrar.bind(versions_command, (_context, _req) => {
    engine: @gateway.engine_version(),
    protocol: @gateway.protocol_version(),
  })
  registrar.bind(invoke_command, (_context, req) => {
    invoke_raw(req.api, req.params.unwrap_or(empty_obj()))
  })
  registrar.bind(collect_command, (_context, req) => collect(req))
  registrar.bind(feed_command, (_context, req) => feed(req))
}

// ── JSON 小工具（gateway protocol.mbt 同形窄面） ──────────────────

///|
fn jget(v : Json, key : String) -> Json {
  match v {
    Object(m) =>
      match m.get(key) {
        Some(x) => x
        None => Json::null()
      }
    _ => Json::null()
  }
}

///|
fn jstr(v : Json) -> String? {
  match v {
    String(s) => Some(s)
    _ => None
  }
}

///|
fn jbool(v : Json) -> Bool? {
  match v {
    True => Some(true)
    False => Some(false)
    _ => None
  }
}

///|
fn jint(v : Json) -> Int32? {
  match v {
    Number(n, repr~) => {
      let float_form = match repr {
        Some(t) => t.contains(".") || t.contains("e") || t.contains("E")
        None => n != n.floor()
      }
      if float_form || n < -2147483648.0 || n > 2147483647.0 {
        None
      } else {
        Some(n.to_int())
      }
    }
    _ => None
  }
}

///|
fn empty_obj() -> Json {
  Json::object(Map([]))
}

///|
fn obj1(k : String, v : Json) -> Json {
  let m : Map[String, Json] = Map([])
  m.set(k, v)
  Json::object(m)
}

///|
fn obj2(k1 : String, v1 : Json, k2 : String, v2 : Json) -> Json {
  let m : Map[String, Json] = Map([])
  m.set(k1, v1)
  m.set(k2, v2)
  Json::object(m)
}

///|
let frame_id : Ref[Int32] = Ref(0)

///|
fn frame_line(api : String, params : Json) -> String {
  frame_id.val += 1
  let m : Map[String, Json] = Map([])
  m.set("id", Json::number(frame_id.val.to_double()))
  m.set("method", Json::string(api))
  m.set("params", params)
  Json::object(m).stringify()
}

// ── 网关调用两层（engine.worker.ts 的 invoke/must 同语义） ─────────

///|
/// 原样转发（错误帧不折叠）——vitro_invoke 出口；顶层帧形状由调用方拆。
fn invoke_raw(api : String, params : Json) -> Json raise EngineError {
  match @gateway.invoke_parsed(frame_line(api, params)) {
    Some(j) => j
    None => raise Frame(message="gateway 响应不可解析（api=\{api}）")
  }
}

///|
fn error_text(e : Json) -> String {
  match e {
    String(s) => s
    Object(_) =>
      match jstr(jget(e, "message")) {
        Some(m) => m
        None => e.stringify()
      }
    Null => "协议错误帧（无错误文本）"
    other => other.stringify()
  }
}

///|
/// must 语义：顶层 ok:false 抛 EngineError；回 result（缺则整帧）。
fn call(api : String, params : Json) -> Json raise EngineError {
  let resp = invoke_raw(api, params)
  if jbool(jget(resp, "ok")) is Some(false) {
    raise Frame(message=error_text(jget(resp, "error")))
  }
  match jget(resp, "result") {
    Null => resp
    r => r
  }
}

// ── collect / feed 编排（序列照抄 engine.worker.ts） ───────────────

///|
/// wire 侧 Latin-1 折回 → UTF-8 还原（stdout/stderr 通道分域解码；
/// note 通道本就是引擎文本域真 UTF-8 直传——engine.worker.ts pullOutputs
/// 同口径）。
fn latin1_to_utf8(s : String) -> String {
  let buf = Buffer()
  for ch in s {
    buf.write_byte((ch.to_int() & 0xFF).to_byte())
  }
  @util.utf8_text_partial(buf.to_bytes())
}

///|
/// 输出四通道收集：output.delta 分页拉到 total（collect/feed 共用）。
fn pull_outputs() -> Json raise EngineError {
  let m : Map[String, Json] = Map([])
  for stream in ["stdout", "stderr", "note"] {
    let acc = StringBuilder()
    let mut cursor = 0
    while true {
      let o = call(
        "output.delta",
        obj2(
          "cursor",
          Json::number(cursor.to_double()),
          "stream",
          Json::string(stream),
        ),
      )
      let delta = jstr(jget(o, "delta")).unwrap_or("")
      if stream == "note" {
        acc.write_string(delta)
      } else {
        acc.write_string(latin1_to_utf8(delta))
      }
      let c = jint(jget(o, "cursor")).unwrap_or(0)
      let total = jint(jget(o, "total")).unwrap_or(0)
      if c >= total || delta == "" {
        break
      }
      cursor = c
    }
    m.set(stream, Json::string(acc.to_string()))
  }
  Json::object(m)
}

///|
/// step.next 收帧循环：waiting/paused/trapped 三停点 + 帧上限
/// （drainSteps 同语义——paused 保留已采帧、trap 文全保留）。
fn drain_steps(cap : Int32) -> (Array[Json], String) raise EngineError {
  let frames : Array[Json] = []
  let mut stopped = ""
  while true {
    let batch = call("step.next", empty_obj())
    match jget(batch, "payloads") {
      Array(ps) =>
        for p in ps {
          frames.push(p)
        }
      _ => ()
    }
    if jbool(jget(batch, "waiting_input")) is Some(true) {
      stopped = "程序等待输入（scanf）——在下方输入框喂入续跑"
      break
    }
    if jbool(jget(batch, "paused")) is Some(true) {
      stopped = "⏸ 已到断点（引擎暂停）——清除断点后 ↻ 重新采集可继续"
      break
    }
    if jbool(jget(batch, "trapped")) is Some(true) {
      stopped = "受检终止：" +
        jstr(jget(batch, "trap_message")).unwrap_or("")
      break
    }
    if jbool(jget(batch, "finished")) is Some(true) || frames.length() >= cap {
      break
    }
  }
  (frames, stopped)
}

///|
fn versions_json() -> Json {
  let m : Map[String, Json] = Map([])
  m.set("engine", Json::string(@gateway.engine_version()))
  m.set("protocol", Json::string(@gateway.protocol_version()))
  Json::object(m)
}

///|
fn run_six(run : Json) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("status", jget(run, "status"))
  m.set("return_value", jget(run, "return_value"))
  m.set("steps_executed", jget(run, "steps_executed"))
  m.set("waiting_input", jget(run, "waiting_input"))
  Json::object(m)
}

///|
/// CollectResult 组装（键名与 demo TS 契约逐字对齐）。
fn collect_result(
  frames : Array[Json],
  stopped : String,
  outputs : Json,
  ms : Int32,
  diagnostics : Json,
  pp_trace : Json,
  compile_ok : Bool,
  run : Json,
) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("frames", Json::array(frames))
  m.set("stopped", Json::string(stopped))
  m.set("outputs", outputs)
  m.set("ms", Json::number(ms.to_double()))
  m.set("versions", versions_json())
  m.set(
    "diagnostics",
    match diagnostics {
      Array(_) => diagnostics
      _ => Json::array([])
    },
  )
  m.set(
    "ppTrace",
    match pp_trace {
      Array(_) => pp_trace
      _ => Json::array([])
    },
  )
  m.set("compileOk", Json::boolean(compile_ok))
  m.set("run", run)
  Json::object(m)
}

///|
fn elapsed_ms(t0 : Int64) -> Int32 {
  (@async.now() - t0).to_int()
}

///|
fn files_json(files : Array[CompileFile]) -> Json {
  Json::array(
    files.map(fn(f) {
      obj2(
        "filename",
        Json::string(f.filename),
        "source",
        Json::string(f.source),
      )
    }),
  )
}

///|
/// 采集编排（collect 同序列）：config.set 漏拉会缺快照面（demo F4 实测
/// 踩坑注释照抄）；断点必须落 step.begin 之后（begin 重建 vm 清旧断点）。
fn collect(req : CollectRequest) -> Json raise EngineError {
  let t0 = @async.now()
  let cap = req.cap.unwrap_or(20000)
  @gateway.reset()
  ignore(call("session.create", empty_obj()))
  ignore(call("config.set", req.cfg.unwrap_or(empty_obj())))
  let comp = call(
    "compile",
    match req.files {
      Some(files) if files.length() > 0 => obj1("files", files_json(files))
      _ => obj1("source", Json::string(req.source.unwrap_or("")))
    },
  )
  let diagnostics = jget(comp, "diagnostics")
  let pp_trace = jget(comp, "preprocessor_trace")
  if !jbool(jget(comp, "ok")).unwrap_or(false) {
    // 编译失败 = 业务域 ok：零帧 + 输出清空（禁陈旧输出滞留）+ stopped 留空
    return collect_result(
      [],
      "",
      empty_obj(),
      elapsed_ms(t0),
      diagnostics,
      pp_trace,
      false,
      Json::null(),
    )
  }
  let run = call(
    "run",
    match req.argv {
      Some(argv) if argv.length() > 0 =>
        obj1("argv", Json::array(argv.map(Json::string)))
      _ => empty_obj()
    },
  )
  ignore(call("step.begin", empty_obj()))
  match req.bp_lines {
    Some(lines) if lines.length() > 0 =>
      ignore(
        call(
          "breakpoints.set",
          obj1(
            "lines",
            Json::array(lines.map(fn(x) { Json::number(x.to_double()) })),
          ),
        ),
      )
    _ => ()
  }
  let (frames, stopped) = drain_steps(cap)
  let capped = frames.length() >= cap
  let final_stopped = if stopped != "" {
    stopped
  } else if capped {
    "已达采集上限 \{cap} 帧（引擎未截断）——可调大上限重采"
  } else {
    ""
  }
  let outputs = pull_outputs()
  collect_result(
    frames,
    final_stopped,
    outputs,
    elapsed_ms(t0),
    diagnostics,
    pp_trace,
    true,
    run_six(run),
  )
}

///|
/// stdin 喂入续跑：feed 改变执行轨迹，重建 step 会话全量重采。
fn feed(req : FeedRequest) -> Json raise EngineError {
  let t0 = @async.now()
  let cap = req.cap.unwrap_or(20000)
  let run = call("input.feed", obj1("text", Json::string(req.text + "\n")))
  ignore(call("step.begin", empty_obj()))
  let (frames, stopped) = drain_steps(cap)
  let outputs = pull_outputs()
  collect_result(
    frames,
    stopped,
    outputs,
    elapsed_ms(t0),
    Json::array([]),
    Json::array([]),
    true,
    run_six(run),
  )
}
