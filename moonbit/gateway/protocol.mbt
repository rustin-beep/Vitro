// NDJSON 帧协议层（自 cmd/serve 上提，S7 批五号——gateway 为 wasm-gc 单出口载体）。
// 照搬 vitro_cli.rs serve 段的帧协议与会话语义；一段方法族 = 协议静态面
//（ping/session.create/reset/destroy/shutdown/config.get/config.set）；
// 二段起接 compile/run/step 等引擎方法（批三号后续段）。

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
/// 参数校验错误帧（#68 报错即文档，2026-10-11）：message 内嵌期望形状、
/// error 附机器可读 `expected` 字段——下游（agent/判分线）可程序化重试，
/// 省一次源码考古。帧结构单源：error 键集 ⊆ @protocol.error_frame_fields_v0_1()
/// （protocol 包白名单，gateway 键集闸锁——防野生键）。expected 形状
/// 词汇表（**冻结面**——下游可编程面，改动属协议演化）：`int`/`string`/
/// `bool` 原语；`T[]` 数组；`{field,field}` 对象（`field?` = 可省略）；
/// `A | B` 任一；`expr[,extra]` 附加可选项。message 为自然语言（各处
/// 自定语序），但帧结构与形状语法**禁逐处手拼**——必须走本函数。
fn serve_param_err(id : Json, message : String, expected : String) -> Json {
  let e : Map[String, Json] = Map([])
  e.set("kind", Json::string("protocol"))
  e.set("message", Json::string(message))
  e.set("expected", Json::string(expected))
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
/// config.get 出口（Rust session_api::config 六字段同构面——MoonBit 侧以
/// SessionConfig 为单一真相源，无「vm None 时回 Null」形态〔vm 非 Option〕；
/// quarantine_budget 的定义点在 MemoryMap〔memory 包——capi 直映射字段〕，
/// 回显直读；input_mode_batch 回显 runtime_batch）。
fn serve_config(s : @session.Session) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("deterministic", s.config.deterministic.to_json())
  m.set("quarantine_budget", s.vm.mem_map.quarantine_budget().to_json())
  m.set("input_mode_batch", s.runtime_batch.to_json())
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
  // 旧引擎与 reset 后的 vm 不再自洽（检查点指向已重置状态）——一并作废
  //（step.begin 无条件新建实例，提前作废无行为差；分叉登记：Rust reset
  // 不显式清 unified，靠 step_begin 覆盖——本侧取保守作废语义）
  s.unified = None
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
  let method_name = match json_field(req, "method").as_string() {
    Some(m) => m
    None =>
      return (
        serve_param_err(
          id, "请求缺少 method 字段（method:string）", "method:string",
        ).stringify(),
        false,
      )
  }
  let params = json_field(req, "params")
  dispatch(s, id, method_name, params)
}

///|
/// 方法分发表（一段静态族；二段起扩引擎方法）。
fn dispatch(
  s : @session.Session,
  id : Json,
  method_name : String,
  params : Json,
) -> (String, Bool) {
  match method_name {
    "ping" => {
      let m : Map[String, Json] = Map([])
      m.set("pong", Json::boolean(true))
      (serve_ok(id, Json::object(m)).stringify(), false)
    }
    "session.create" => {
      // Rust create = Session::default()（runtime 域全清）——与 reset 的
      // 「保留」语义分界：argv/输入模式在 create/destroy 时回默认
      reset_session_preserving_config(s)
      s.runtime_argv = []
      s.runtime_batch = false
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
      // 同 create：Rust destroy = Session::default()——runtime 域全清
      reset_session_preserving_config(s)
      s.runtime_argv = []
      s.runtime_batch = false
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
    "config.set" =>
      // 帧结构对齐 Rust（serve 臂：serve_ok(id, cfg)）——一段写成裸
      // config 对象回串（无 id/ok 包装），serve_smoke 双宿主对拍实锤
      // （响应 id 一一对应 + 帧同构两断言红）；既有锚只 contains 数字
      // 未锁帧结构故未暴露
      (serve_ok(id, serve_apply_config(s, params)).stringify(), false)
    // 静态元数据族（三段）
    "capabilities" => serve_capabilities_frame(id)
    "error_catalog" => serve_error_catalog_frame(id)
    "semantic_labels" => serve_semantic_labels_frame(id)
    "contracts" => serve_contracts_frame(id)
    // 图标资产通道（#27 方案 C——业务帧只带语义 id，资产经此按 digest 下发）
    "icons.get" => serve_icons_get_frame(id, params)
    // 引擎方法族（二段起）
    "compile" => serve_compile_frame(s, id, params)
    "run" => serve_run_frame(s, id, params)
    "input.feed" => serve_input_feed_frame(s, id, params)
    "output.delta" => serve_output_delta_frame(s, id, params)
    "memory.regions" => serve_memory_regions_frame(s, id)
    "memory.dump" => serve_memory_dump_frame(s, id)
    // step 族五方法（S8 批一号接线——编排本体 time_travel.UnifiedEngine）
    "step.begin" => serve_step_begin_frame(s, id, params)
    "step.next" => serve_step_next_frame(s, id, params)
    "payload.get" => serve_payload_get_frame(s, id, params)
    "seek" => serve_seek_frame(s, id, params)
    "breakpoints.set" => serve_breakpoints_set_frame(s, id, params)
    // dump 族四方法（只读语义——独立通道不碰会话态；diagnostics_probe
    // 段三接线 2026-10-02：一次性会话承载管线，认知链八段导出）
    "ast.dump" => serve_ast_dump_frame(s, id, params)
    "typeck.dump" => serve_typeck_dump_frame(s, id, params)
    "symbols.dump" => serve_symbols_dump_frame(s, id, params)
    "diagnostics_probe" => serve_diagnostics_probe_frame(s, id, params)
    _ =>
      (
        serve_err(
          id,
          "protocol",
          "未知方法：\{method_name}（已接：ping/capabilities/error_catalog/semantic_labels/contracts/icons.get/session.create/reset/destroy/config.get/config.set/compile/run/input.feed/output.delta/memory.regions/memory.dump/step.begin/step.next/payload.get/seek/breakpoints.set/shutdown；dump 族已接：ast/typeck/symbols/diagnostics_probe）",
        ).stringify(),
        false,
      )
  }
}

///|
/// config.set（与 Rust serve_apply_config 同批字段）。quarantine_budget：
/// clamp 0..1MB（Rust 同形）直写 MemoryMap 定义点（memory 包——capi
/// `vitro_set_quarantine_budget` 直映射字段；vm reset 跨重建保留 ⇒
/// 会话级语义由 reset 纪律承担，无需 SessionConfig 双写）。
fn serve_apply_config(s : @session.Session, params : Json) -> Json {
  match json_field(params, "quarantine_budget").as_int() {
    Some(v) => {
      let clamped = if v < 0 { 0 } else if v > 1048576 { 1048576 } else { v }
      s.vm.mem_map.set_quarantine_budget(clamped)
    }
    None => ()
  }
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
/// as_string/as_bool 有意遮蔽 core 同名方法（对齐 serde_json 命名）——
/// 0050 警告以此豁免，core 升级时复核（#54 A3 登记 2026-10-09）。
fn Json::as_string(self : Json) -> String? {
  match self {
    String(s) => Some(s)
    _ => None
  }
}

///|
/// 整数语义访问器（serde_json `as_i64` 对齐，2026-10-02 审阅 P3 修复）：
/// 浮点形态（原文含 '.'/'e'/'E'——json_parse 恒保 repr）恒 None，
/// 整数文本超 i32 域丢弃（Double::to_int 溢出防护；错误码/协议参数域
/// 远离边界——i64 内超 i32 的病态截断语义不照搬，此处收窄丢弃）。
/// repr=None（手工构造）退值域判 n==n.floor()。
fn Json::as_int(self : Json) -> Int? {
  match self {
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
fn Json::as_bool(self : Json) -> Bool? {
  match self {
    True => Some(true)
    False => Some(false)
    _ => None
  }
}
