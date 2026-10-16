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
  m.set("quarantine_budget", Json(s.vm.mem_map.quarantine_budget()))
  m.set("input_mode_batch", Json(s.runtime_batch))
  m.set("compiled", Json(s.compile.compiled))
  m.set("max_steps", Json(s.config.max_steps))
  m.set("call_depth_limit", Json(s.config.call_depth_limit))
  // #91（2026-10-14）：输出预算现值（判分方提前判断天花板——issue 建议①）
  m.set("output_budget", Json(s.vm.output.budget()))
  // #133（2026-10-16）：preset 档位回显——按当前配置值**推断**（显式
  // 单键覆盖后档名可能与逐项值不一致，推断口径 = 四键全等于某档的
  // 展开值才认档，否则 "custom"——诚实呈现而非记名）。config.get 面
  // 是只读回显（协议「只增不改」），消费方可忽略。
  let ms = s.config.max_steps
  let cd = s.config.call_depth_limit
  let ob = s.vm.output.budget()
  let preset = if ms == 10000000 && cd == 10000 && ob == 16777216 {
    "default"
  } else if ms == 2000000000 && cd == 100000 && ob == 67108864 {
    "algo"
  } else if ms == 100000 && cd == 1000 && ob == 4194304 {
    "tiny"
  } else {
    "custom"
  }
  m.set("preset", Json::string(preset))
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
  let req : Json = @util.json_parse(line) catch {
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
      // #105（2026-10-14）：未知键 fail loud——config.set 是纯配置通道，
      // 旧对未知键静默丢弃（input_mode_batch 实测被吞）；白名单先行 +
      // serve_param_err 报错即文档（#68 单源）。run 帧内联的
      // serve_apply_config 不做白名单（混合域宽进）
      // #131/#133 处置（2026-10-16）：int 域配置键「在场但值不可解析」
      // fail loud——超 Int32 域（如 max_steps=3e9——A* 大搜索真实撞面）、
      // 浮点形态（1e9 写成 1.5e9）曾静默跳过（as_int()=None 走缺省分支，
      // 响应 ok:true 配置保持旧值——clamped 空 = 下游零感知）。白名单后、
      // apply 前统一预检（单点 helper，禁逐键手拼——#68 单编码者原则）。
      // run 帧内联的 serve_apply_config 不做本预检（run 是宽进域，历史
      // 行为冻结——protocol_frames 基线零重冻）。
      match config_set_unknown_key(params) {
        Err(unknown) =>
          (
            serve_param_err(
              id,
              "config.set 收到未知配置键 '\{unknown}'（合法键：deterministic / quarantine_budget / max_steps / call_depth_limit / output_budget / input_mode_batch / preset〔default|algo|tiny——#133 档位开关〕）",
              "{preset?:\"default|algo|tiny\", deterministic?:bool, quarantine_budget?:int, max_steps?:int, call_depth_limit?:int, output_budget?:int, input_mode_batch?:bool}",
            ).stringify(),
            false,
          )
        // #133：非法档名 fail loud（静默忽略 = 档位开关形同虚设）
        Ok(_) if json_field(params, "preset") is String(bad) &&
          !(bad == "default" || bad == "algo" || bad == "tiny") =>
          (
            serve_param_err(
              id,
              "config.set 的 preset 值 '\{bad}' 不存在（合法档：default=语法教学缺省 / algo=算法作业大搜索〔步数 2e9+深度 100K+输出 64M〕 / tiny=微演示〔10 万步〕——同帧显式键可覆盖单项）",
              "preset:\"default\"|\"algo\"|\"tiny\"",
            ).stringify(),
            false,
          )
        Ok(_) =>
          // 值域预检：max_steps 1..=2147483647（引擎步数计数 Int32 顶）
          match config_int_field_overflow(params, "max_steps", 2147483647) {
            Err(msg) =>
              (
                serve_param_err(
                  id,
                  "config.set 的 max_steps 值不可用：\{msg}（步数计数上限 2147483647——更大负载请分批推进或减小问题规模；内存上限归 1MB 白箱模型，见 #133 扩展段方案）",
                  "max_steps:int(1..=2147483647)",
                ).stringify(),
                false,
              )
            Ok(_) => {
              // #94（2026-10-15）：回包 result 追加 clamped 键名数组（恒带；
              // 空数组=无钳制）——协议「只增不改」。config.get 面零变更。
              let (cfg, clamped_keys) = serve_apply_config(s, params)
              match cfg {
                Object(m) => {
                  let arr : Array[Json] = []
                  for k in clamped_keys {
                    arr.push(Json::string(k))
                  }
                  m.set("clamped", Json::array(arr))
                  (serve_ok(id, Json::object(m)).stringify(), false)
                }
                _ => (serve_ok(id, cfg).stringify(), false)
              }
            }
          }
      }
    // 静态元数据族（三段）
    "capabilities" => serve_capabilities_frame(id)
    "error_catalog" => serve_error_catalog_frame(id)
    "semantic_labels" => serve_semantic_labels_frame(id)
    "contracts" => serve_contracts_frame(id)
    // 43 族算法目录（#36——判据源码即数据源的静态导出）
    "algorithms.catalog" => serve_algorithms_catalog_frame(id)
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
          "未知方法：\{method_name}（已接：ping/capabilities/error_catalog/semantic_labels/contracts/algorithms.catalog/icons.get/session.create/reset/destroy/config.get/config.set/compile/run/input.feed/output.delta/memory.regions/memory.dump/step.begin/step.next/payload.get/seek/breakpoints.set/shutdown；dump 族已接：ast/typeck/symbols/diagnostics_probe）",
        ).stringify(),
        false,
      )
  }
}

///|
/// #133 止血包（2026-10-16）：int 域配置键的值域预检——键在场但
/// `as_int()` 不可解析（超 Int32 域 / 浮点形态 / 非数值）时 Err(人类可读
/// 原因)，键不在场或值合法返回 Ok。单源 helper（#68 禁逐键手拼）。
fn config_int_field_overflow(
  params : Json,
  key : String,
  hi : Int32,
) -> Result[Unit, String] {
  match json_field(params, key) {
    // 键不在场（json_field 缺省 Null）——不适用值域检查
    Null => Ok(())
    Number(n, repr~) => {
      let float_form = match repr {
        Some(t) => t.contains(".") || t.contains("e") || t.contains("E")
        None => n != n.floor()
      }
      if float_form {
        return Err("浮点形态 '\{n}' 不是整数")
      }
      // 只查上界（超 Int32 域的不可表示值——as_int() 丢失即静默 bug 面）；
      // 下界不动：低下界的钳制语义（#94 的 clamped 显式化）保留在
      // serve_apply_config（0/-1 → 钳 1 + clamped 标记，非报错）
      if n > hi.to_double() {
        return Err("值 \{n} 超出可表示上限 \{hi}")
      }
      Ok(())
    }
    String(s) => Err("收到字符串 '\{s}'——须为 JSON 数值")
    other => Err("类型不可用（\{other}）——须为 JSON 整数")
  }
}

///|
/// #105：config.set 白名单校验——params 里首个不在合法键集内的键名
/// （Err(键名)）；全部合法返回 Ok。空/非对象 params 视为合法（键为零）。
fn config_set_unknown_key(params : Json) -> Result[Unit, String] {
  let legal = [
    "deterministic", "quarantine_budget", "max_steps", "call_depth_limit", "output_budget",
    "input_mode_batch", "preset",
  ]
  match params {
    Object(m) => {
      for k, _ in m {
        let known = legal.exists(l => l == k)
        if !known {
          return Err(k)
        }
      }
      Ok(())
    }
    _ => Ok(())
  }
}

///|
/// config.set（与 Rust serve_apply_config 同批字段）。quarantine_budget：
/// clamp 0..1MB（Rust 同形）直写 MemoryMap 定义点（memory 包——capi
/// `vitro_set_quarantine_budget` 直映射字段；vm reset 跨重建保留 ⇒
/// 会话级语义由 reset 纪律承担，无需 SessionConfig 双写）。
/// 返回 (生效后配置, 被钳制键名数组)——#94：钳制须对下游显式（静默
/// 钳制 = 引擎替下游做决定却不告知，issue 实测 4MiB 压回 1MiB 判题
/// 缓冲在半路受检）；数组按本函数判定序收集。
fn serve_apply_config(
  s : @session.Session,
  params : Json,
) -> (Json, Array[String]) {
  let clamped_keys : Array[String] = []
  // #133 止血包（2026-10-16）：preset 档位开关——「algo」（算法作业档：
  // 步数 2e9/深度 100K/隔离 1M/输出 64M——#131 学生 A* 实测合法负载
  // 1.56e9 步的承接档）先展开为显式键，同帧显式键再覆盖单项（组合
  // 直观：{"preset":"algo","max_steps":5e8}）。default 档 = 全缺省值
  // 显式展开（值同现状——非空操作：把档内的会话拉回缺省）。内存上限
  // 不做键（1MB 白箱模型——扩展段归 #133 主体批）。
  match json_field(params, "preset") {
    String(p) =>
      match p {
        "default" => {
          s.set_max_steps(10000000)
          s.set_call_depth_limit(10000)
          s.vm.mem_map.set_quarantine_budget(262144)
          s.vm.output.set_budget(16777216)
        }
        "algo" => {
          s.set_max_steps(2000000000)
          s.set_call_depth_limit(100000)
          s.vm.mem_map.set_quarantine_budget(1048576)
          s.vm.output.set_budget(67108864)
        }
        "tiny" => {
          s.set_max_steps(100000)
          s.set_call_depth_limit(1000)
          s.vm.mem_map.set_quarantine_budget(65536)
          s.vm.output.set_budget(4194304)
        }
        _ => ()
      }
    _ => ()
  }
  match json_field(params, "quarantine_budget").as_int() {
    Some(v) => {
      let clamped = if v < 0 { 0 } else if v > 1048576 { 1048576 } else { v }
      if clamped != v {
        clamped_keys.push("quarantine_budget")
      }
      s.vm.mem_map.set_quarantine_budget(clamped)
    }
    None => ()
  }
  match json_field(params, "max_steps").as_int() {
    Some(v) => {
      if v < 1 {
        clamped_keys.push("max_steps")
      }
      s.set_max_steps(v)
    }
    None => ()
  }
  match json_field(params, "call_depth_limit").as_int() {
    Some(v) => {
      if v < 16 {
        clamped_keys.push("call_depth_limit")
      }
      s.set_call_depth_limit(v)
    }
    None => ()
  }
  match json_field(params, "deterministic").as_bool() {
    Some(v) => {
      s.config.deterministic = v
      s.config.apply_to_vm(s.vm)
    }
    None => ()
  }
  // #105（2026-10-14）：input_mode_batch 真支持——写会话态 + 即时应用
  // InputState（run 帧 batch_input 同款形态；#88 实测三条失效路径之一
  // 的 config 通道自此打通）
  match json_field(params, "input_mode_batch").as_bool() {
    Some(v) => {
      s.runtime_batch = v
      s.vm.set_input(@host.InputState::new(s.vm.input.lines, v))
    }
    None => ()
  }
  // #91（2026-10-14）：输出预算会话级可调——判分/下游可控小预算快测
  // 截断行为；clamp [4KB, 16MB]（下限防诊断通道自吞、上限=默认防调大
  // 绕安全网）
  match json_field(params, "output_budget").as_int() {
    Some(v) => {
      let clamped = if v < 4096 {
        4096
      } else if v > 16777216 {
        16777216
      } else {
        v
      }
      if clamped != v {
        clamped_keys.push("output_budget")
      }
      s.vm.output.set_budget(clamped)
    }
    None => ()
  }
  (serve_config(s), clamped_keys)
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
fn Json::as_int(self : Json) -> Int32? {
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
