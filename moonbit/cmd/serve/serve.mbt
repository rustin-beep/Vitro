// serve 主循环与协议层（S7 批三号一段，2026-09-28）。
// 照搬 vitro_cli.rs serve 段的帧协议与会话语义；一段方法族 = 协议静态面
//（ping/session.create/reset/destroy/shutdown/config.get/config.set）；
// 二段起接 compile/run/step 等引擎方法（批三号后续段）。

///|
#borrow(buf)
extern "C" fn serve_read_line_stub(buf : Bytes, cap : Int) -> Int = "moonbit_vitro_serve_read_line"

///|
const SERVE_LINE_CAP : Int = 65536

///|
/// 成功帧：{id, ok:true, result}。
fn serve_ok(id : Json, result : Json) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("id", id)
  m.set("ok", Json::boolean(true))
  m.set("result", result)
  Json::object(m)
}

///|
/// 错误帧：{id, ok:false, error:{kind,message}}——与成功帧同构（B 级锚）。
fn serve_err(id : Json, kind : String, message : String) -> Json {
  let e : Map[String, Json] = Map([])
  e.set("kind", Json::string(kind))
  e.set("message", Json::string(message))
  let m : Map[String, Json] = Map([])
  m.set("id", id)
  m.set("ok", Json::boolean(false))
  m.set("error", Json::object(e))
  Json::object(m)
}

///|
/// 会话拓扑语义（下游需求清单 D2）：单 serve 进程 = 单活跃会话。
fn serve_session_semantics() -> Json {
  let m : Map[String, Json] = Map([])
  m.set("model", Json::string("single-active-session"))
  m.set("active_sessions", Json::number(1))
  m.set("concurrent_sessions", Json::boolean(false))
  m.set("handle_parameter", Json::boolean(false))
  m.set(
    "create_semantics",
    Json::string("clear-and-rebuild（清空重建同一实例）"),
  )
  m.set(
    "reset_semantics",
    Json::string(
      "清空编译/运行状态，保留会话级配置（隔离预算/deterministic/argv）",
    ),
  )
  m.set(
    "destroy_semantics",
    Json::string(
      "清空重建（进程存活；如需回收进程请用 shutdown）",
    ),
  )
  m.set(
    "concurrency_recommendation",
    Json::string("并发场景起多个 serve 进程"),
  )
  Json::object(m)
}

///|
/// config.get 出口（Rust session_api::config 同构面——MoonBit 侧以
/// SessionConfig 为单一真相源，无「vm None 时回 Null」形态〔vm 非 Option〕；
/// quarantine_budget/input_mode_batch/argv 等运行态字段随二段接线补）。
fn serve_config(s : @session.Session) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("deterministic", s.config.deterministic.to_json())
  m.set("compiled", s.compile.compiled.to_json())
  m.set("max_steps", s.config.max_steps.to_json())
  m.set("call_depth_limit", s.config.call_depth_limit.to_json())
  Json::object(m)
}

///|
/// 会话重置（R3 单源语义：清空编译/运行态，保留会话级配置）。
fn reset_session_preserving_config(s : @session.Session) -> Unit {
  let cfg = s.config
  ignore(cfg)
  // 整体重建（新 Session）+ 配置回放——MoonBit 侧 Session 非 Copy，经
  // 字段级重建：compile 清空、vm reset（reset 本身保留会话级配置——
  // vm/state.mbt 纪律，双保险语义同 Rust 的 mem::take 回放形态）
  s.compile = @session.CompileState::new()
  s.vm.reset()
  s.unified_pending = None
  s.unified_last_line = 0
  s.unified_last_frame_vars = []
  s.unified_row_entry_vars = []
}

///|
/// 单行请求处理（纯函数——白盒直测协议层）。
/// 返回 (响应 JSON 串, 是否继续)。
fn serve_handle(s : @session.Session, line : String) -> (String, Bool) {
  let req : Json = json_parse(line) catch {
    _ =>
      return (
        serve_err(Json::null(), "protocol", "非法 JSON 请求").stringify(),
        false,
      )
  }
  let id = json_field(req, "id")
  let method = match json_field(req, "method").as_string() {
    Some(m) => m
    None =>
      return (
        serve_err(id, "protocol", "请求缺少 method 字段").stringify(),
        false,
      )
  }
  let params = json_field(req, "params")
  dispatch(s, id, method, params)
}

///|
/// 方法分发表（一段静态族；二段起扩引擎方法）。
fn dispatch(
  s : @session.Session,
  id : Json,
  method : String,
  params : Json,
) -> (String, Bool) {
  match method {
    "ping" => {
      let m : Map[String, Json] = Map([])
      m.set("pong", Json::boolean(true))
      (serve_ok(id, Json::object(m)).stringify(), false)
    }
    "session.create" => {
      reset_session_preserving_config(s)
      let m : Map[String, Json] = Map([])
      m.set("created", Json::boolean(true))
      m.set("session", serve_session_semantics())
      m.set("config", serve_config(s))
      (serve_ok(id, Json::object(m)).stringify(), false)
    }
    "session.reset" => {
      reset_session_preserving_config(s)
      let m : Map[String, Json] = Map([])
      m.set("reset", Json::boolean(true))
      m.set("session", serve_session_semantics())
      m.set("config", serve_config(s))
      (serve_ok(id, Json::object(m)).stringify(), false)
    }
    "session.destroy" => {
      reset_session_preserving_config(s)
      let m : Map[String, Json] = Map([])
      m.set("destroyed", Json::boolean(true))
      m.set("session", serve_session_semantics())
      (serve_ok(id, Json::object(m)).stringify(), false)
    }
    "shutdown" => {
      let m : Map[String, Json] = Map([])
      m.set("shutdown", Json::boolean(true))
      (serve_ok(id, Json::object(m)).stringify(), true)
    }
    "config.get" => (serve_ok(id, serve_config(s)).stringify(), false)
    "config.set" => (serve_apply_config(s, params).stringify(), false)
    _ =>
      (
        serve_err(
          id,
          "protocol",
          "未知方法：\{method}（一段静态族已接：ping/session.create/reset/destroy/config.get/config.set/shutdown；引擎方法随批三号后续段接入）",
        ).stringify(),
        false,
      )
  }
}

///|
/// config.set（与 Rust serve_apply_config 同批字段；quarantine_budget
/// 等运行态字段随二段接线）。
fn serve_apply_config(s : @session.Session, params : Json) -> Json {
  match json_field(params, "max_steps").as_int() {
    Some(v) => s.set_max_steps(v)
    None => ()
  }
  match json_field(params, "call_depth_limit").as_int() {
    Some(v) => s.set_call_depth_limit(v)
    None => ()
  }
  match json_field(params, "deterministic").as_bool() {
    Some(v) => {
      s.config.deterministic = v
      s.config.apply_to_vm(s.vm)
    }
    None => ()
  }
  serve_config(s)
}

///|
/// Json 对象字段取值（非对象/缺字段返回 Null）。
fn json_field(v : Json, key : String) -> Json {
  match v {
    Object(m) => m.get(key) |> unwrap_or_null
    _ => Json::null()
  }
}

///|
fn unwrap_or_null(v : Json?) -> Json {
  match v {
    Some(j) => j
    None => Json::null()
  }
}

///|
/// Json 值访问器族（serve 协议层的窄面：id 透传只 stringify 不解构）。
fn Json::as_string(self : Json) -> String? {
  match self {
    String(s) => Some(s)
    _ => None
  }
}

///|
fn Json::as_int(self : Json) -> Int? {
  match self {
    Number(n) => Some(n.to_int())
    _ => None
  }
}

///|
fn Json::as_bool(self : Json) -> Bool? {
  match self {
    True => Some(true)
    False => Some(false)
    _ => None
  }
}

///|
/// serve 主循环：stdin 逐行 → serve_handle → stdout 响应；shutdown 停。
fn main {
  let s = @session.Session::new()
  let buf : Bytes = Bytes::make(SERVE_LINE_CAP, b'\x00')
  while true {
    let n = serve_read_line_stub(buf, SERVE_LINE_CAP)
    if n < 0 {
      break // EOF（-1）或超长行（-2 视协议错退出）
    }
    let line = buf[:n].to_string()
    let (resp, stop) = serve_handle(s, line)
    println(resp)
    if stop {
      break
    }
  }
}
