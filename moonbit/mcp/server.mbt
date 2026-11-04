// MCP server 核心：JSON-RPC 方法分发（initialize / ping / tools/list /
// tools/call / notifications）+ 渐进披露状态机 + 会话寻址。
// 披露判据：L1 可见 ⇔ 会话池非空；每次 handle_line 入口（过期逐出后）与
// 出口（工具调用后）各对账一次，翻转即发 notifications/tools/list_changed
// （布尔级切换——一次会话生命周期内工具集稳定，KV-cache 只在开关各失效一次）。

///|
/// 壳层钩子（本包零 IO——stdin/stdout/文件/截图/墙钟全部经此注入；
/// `moon test` 用桩钩子即可全量覆盖 12 工具）。
pub(all) struct Host {
  /// 墙钟毫秒（会话过期判定 / 耗时统计）。
  clock_ms : () -> Double
  /// 渲染落盘（HTML 模板 + 文件写 + 可选 PNG 截图归壳层——浏览器资产）。
  /// 入参 {mode,title,source,frames,focus,algo,run,outputs,diagnostics,
  /// compile_ok,warnings,theme,audio,thinned,raw_count,versions,out_dir,
  /// preview_png,slug}；返回 {ok,html_path,size_bytes,preview_png_path?,
  /// preview_png_b64?,warnings[],error?}。
  render : (Json) -> Json
}

///|
pub struct Server {
  host : Host
  entries : Map[String, Entry]
  mut initialized : Bool
  mut l1_visible : Bool
  mut seq : Int32
}

///|
const SERVER_NAME : String = "vitro-dsh-plugin"

///|
const SERVER_VERSION : String = "0.2.0"

///|
/// 缺省协议版本（ToolAnnotations/readOnlyHint 自 2025-03-26 起入规范；客户端
/// 显式给出时回显其值——v1 同款宽容）。
const MCP_PROTOCOL_VERSION : String = "2025-03-26"

///|
pub fn Server::new(host~ : Host) -> Server {
  { host, entries: Map([]), initialized: false, l1_visible: false, seq: 0, }
}

///|
fn Server::now(self : Server) -> Double {
  (self.host.clock_ms)()
}

///|
/// 披露态对账：翻转则推 list_changed 通知。
fn Server::sync_disclosure(self : Server, out : Array[String]) -> Unit {
  let vis = self.entries.length() > 0
  if vis != self.l1_visible {
    self.l1_visible = vis
    out.push(
      rpc_notification(
        "notifications/tools/list_changed",
        Json::object(Map([])),
      ),
    )
  }
}

///|
/// 单行请求 → 0..n 行输出（响应帧 + 可能的通知帧，均为完整 JSON 行、不带换行）。
pub fn Server::handle_line(self : Server, line : String) -> Array[String] {
  let out : Array[String] = []
  let now = self.now()
  ignore(pool_evict_expired(self.entries, now))
  self.sync_disclosure(out)
  let t = trim_ws(line)
  if t.length() == 0 {
    return out
  }
  let req = match parse_request(t) {
    Ok(r) => r
    Err(m) => {
      out.push(rpc_error(Json::null(), -32700, m))
      return out
    }
  }
  if req.method_name.length() == 0 {
    if req.has_id {
      out.push(rpc_error(req.id, -32600, "缺 method 的请求"))
    }
    return out
  }
  match req.method_name {
    // PR #457 审阅 v2 P2-3：请求形态方法（initialize/ping/tools/list/
    // tools/call）无 id = 通知形态——JSON-RPC 通知无响应帧、MCP 亦未定义
    // 这些方法的通知语义 → 不执行不回（修前 tools/call 通知形态会真创建
    // 会话并回 id:null 帧，严格客户端按协议错处理）
    "initialize" =>
      if req.has_id {
        self.initialized = true
        let pv = jstr_or(
          jget(req.params, "protocolVersion"),
          MCP_PROTOCOL_VERSION,
        )
        let r = ob()
          .s("protocolVersion", pv)
          .j(
            "capabilities",
            ob().j("tools", ob().b("listChanged", true).done()).done(),
          )
          .j(
            "serverInfo",
            ob().s("name", SERVER_NAME).s("version", SERVER_VERSION).done(),
          )
          .s(
            "instructions", "Vitro C 代码执行动画（Serena 形态有状态会话）。一次性出动画：animate(source)。教学引导/质量调优：session_open(source) 解锁会话工具（会收到 tools/list_changed，请重拉 tools/list）→ frames_summary 看结构 → annotations/frames_query 下钻 → run_to/step_next 导游式推进 → render 出 HTML → 用 DSH present 工具交付 html_path。只读探查工具带 readOnlyHint。",
          )
          .done()
        out.push(rpc_result(req.id, r))
      }
    "notifications/initialized" | "initialized" | "notifications/cancelled" =>
      ()
    "ping" =>
      if req.has_id {
        out.push(rpc_result(req.id, Json::object(Map([]))))
      }
    "tools/list" =>
      if req.has_id {
        out.push(rpc_result(req.id, tools_list_json(self.l1_visible)))
      }
    "tools/call" =>
      if req.has_id {
        match self.call_tool(req.params, now) {
          Done(r) => out.push(rpc_result(req.id, r))
          Proto(code, m) => out.push(rpc_error(req.id, code, m))
          Fail(m) => out.push(rpc_result(req.id, tool_error(m)))
        }
      }
    other =>
      if req.has_id {
        out.push(rpc_error(req.id, -32601, "未知方法: \{other}"))
      }
  }
  self.sync_disclosure(out)
  out
}

///|
/// tools/call 分发。
fn Server::call_tool(self : Server, params : Json, now : Double) -> ToolOut {
  let name = jstr_or(jget(params, "name"), "")
  let args = match jget(params, "arguments") {
    Object(_) as a => a
    _ => Json::object(Map([]))
  }
  guard find_tool(name) is Some(t) else {
    let avail = tool_names(0)
    if self.l1_visible {
      for n in tool_names(1) {
        avail.push(n)
      }
    }
    let joined = StringBuilder()
    for i, n in avail {
      if i > 0 {
        joined.write_string(", ")
      }
      joined.write_string(n)
    }
    return Proto(
      -32602,
      "未知工具: \{name}（可用：\{joined.to_string()}）",
    )
  }
  if t.level == 1 && !self.l1_visible {
    return Fail(
      "工具 \{name} 属会话层（L1），当前无活跃会话——先 session_open(source) 解锁；若会话已过期（空闲 5 分钟）请重新打开",
    )
  }
  match name {
    "animate" => self.tool_animate(args, now)
    "diagnose" => self.tool_diagnose(args, now)
    "capabilities" => self.tool_capabilities()
    "sessions" =>
      Done(
        tool_text(ob().j("sessions", pool_list_json(self.entries, now)).done()),
      )
    "session_open" => self.tool_session_open(args, now)
    "frames_summary" => self.tool_frames_summary(args, now)
    "frames_query" => self.tool_frames_query(args, now)
    "annotations" => self.tool_annotations(args, now)
    "run_to" => self.tool_run_to(args, now)
    "step_next" => self.tool_step_next(args, now)
    "render" => self.tool_render(args, now)
    "session_close" => self.tool_session_close(args, now)
    _ => Proto(-32602, "未知工具: \{name}")
  }
}

///|
/// 会话寻址：显式 session_id 或最近使用的会话；刷新 last_used。
fn Server::resolve(
  self : Server,
  args : Json,
  now : Double,
) -> Result[Entry, String] {
  let id = match jstr(jget(args, "session_id")) {
    Some(s) => s
    None =>
      match pool_most_recent(self.entries) {
        Some(s) => s
        None => return Err("无活跃会话——先 session_open(source)")
      }
  }
  match pool_touch(self.entries, id, now) {
    Some(e) => Ok(e)
    None =>
      Err(
        "会话 \{id} 不存在或已过期（空闲 5 分钟逐出 / LRU 上限 8）——重新 session_open；sessions() 可查活跃列表",
      )
  }
}

///|
fn pad4(n : Int32) -> String {
  let s = n.to_string()
  if s.length() >= 4 {
    s
  } else {
    let b = StringBuilder()
    for i = s.length(); i < 4; i = i + 1 {
      b.write_char('0')
    }
    b.write_string(s)
    b.to_string()
  }
}
