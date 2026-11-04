// JSON-RPC 2.0 帧层（MCP stdio 传输 = 行分隔 JSON-RPC）。
// 帧形态单源：成功 {jsonrpc,id,result} / 错误 {jsonrpc,id,error:{code,message}} /
// 通知 {jsonrpc,method,params}（无 id）。错误码按规范：-32700 解析 / -32600
// 请求非法 / -32601 方法未知 / -32602 参数非法 / -32603 内部错误。

///|
priv struct RpcReq {
  id : Json
  has_id : Bool
  method_name : String
  params : Json
}

///|
/// 单行 → 请求（Err = 解析失败文案；缺 method 由调用方按 has_id 决定是否回错）。
fn parse_request(line : String) -> Result[RpcReq, String] {
  let v = @util.json_parse(line) catch {
    _ => return Err("Parse error（须为行分隔 JSON-RPC 2.0）")
  }
  guard v is Object(_) else { return Err("请求须为 JSON 对象") }
  let id = jget(v, "id")
  let has_id = !jis_null(id)
  let method_name = jstr_or(jget(v, "method"), "")
  let params = jget(v, "params")
  Ok({ id, has_id, method_name, params, })
}

///|
fn rpc_result(id : Json, result : Json) -> String {
  ob().s("jsonrpc", "2.0").j("id", id).j("result", result).done().stringify()
}

///|
fn rpc_error(id : Json, code : Int32, message : String) -> String {
  ob()
  .s("jsonrpc", "2.0")
  .j("id", id)
  .j("error", ob().n("code", code).s("message", message).done())
  .done()
  .stringify()
}

///|
fn rpc_notification(method_name : String, params : Json) -> String {
  ob()
  .s("jsonrpc", "2.0")
  .s("method", method_name)
  .j("params", params)
  .done()
  .stringify()
}

///|
/// MCP tools/call 成功结果包裹（规范：result 一律 {content:[...], isError}）。
fn tool_text(body : Json) -> Json {
  let block = ob().s("type", "text").s("text", body.stringify(indent=1)).done()
  ob().a("content", [block]).b("isError", false).done()
}

///|
/// 文本 + PNG 图像块（animate/render 的预览通道——DSH 只收 text/image 块）。
fn tool_text_image(body : Json, png_b64 : String) -> Json {
  let t = ob().s("type", "text").s("text", body.stringify(indent=1)).done()
  let img = ob()
    .s("type", "image")
    .s("data", png_b64)
    .s("mimeType", "image/png")
    .done()
  ob().a("content", [t, img]).b("isError", false).done()
}

///|
/// 工具级失败（规范：执行失败进 result.isError=true，让模型可见可处置；
/// 协议级失败才走 JSON-RPC error）。
fn tool_error(message : String) -> Json {
  let block = ob().s("type", "text").s("text", message).done()
  ob().a("content", [block]).b("isError", true).done()
}

///|
/// 工具处理结果：Ok(已包裹的 result) / Proto(协议错码, 文案) / Fail(工具级文案)。
priv enum ToolOut {
  Done(Json)
  Proto(Int32, String)
  Fail(String)
}
