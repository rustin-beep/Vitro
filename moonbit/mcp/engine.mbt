// 引擎通道：Entry.session 经 `@gateway.invoke_on` 走 NDJSON 帧协议（与
// wasm 宿主/CLI 完全同一协议面——单真相源，mcp 层不碰引擎内部结构）。
// 响应信封 {id, ok, result | error{kind,message}} 在此解封。

///|
/// 方法调用：Ok(result) / Err("[kind] message")。
fn entry_call(
  e : Entry,
  method_name : String,
  params : Json,
) -> Result[Json, String] {
  e.seq += 1
  let req = ob()
    .n("id", e.seq)
    .s("method", method_name)
    .j("params", params)
    .done()
  let text = @gateway.invoke_on(e.session, req.stringify())
  let resp = @util.json_parse(text) catch {
    _ => return Err("[protocol] 引擎响应非 JSON（\{method_name}）")
  }
  match jbool(jget(resp, "ok")) {
    Some(true) => Ok(jget(resp, "result"))
    _ => {
      let er = jget(resp, "error")
      let kind = jstr_or(jget(er, "kind"), "?")
      let msg = jstr_or(jget(er, "message"), "引擎错误")
      Err("[\{kind}] \{msg}")
    }
  }
}

///|
fn entry_call0(e : Entry, method_name : String) -> Result[Json, String] {
  entry_call(e, method_name, Json::object(Map([])))
}

///|
/// 版本对（gateway 单源常量）。
fn engine_versions() -> Json {
  ob()
  .s("engine", @gateway.engine_version())
  .s("protocol", @gateway.protocol_version())
  .done()
}

///|
/// 标准会话开场：session.create → config.set（漏调 = 快照面全空，v1 实测坑）
/// → compile。返回 compile 的 result（含 ok/diagnostics/algorithm_matches）。
fn open_and_compile(
  e : Entry,
  source : String,
  files : Array[Json],
  preset : String,
) -> Result[Json, String] {
  guard entry_call0(e, "session.create") is Ok(_) else {
    return Err("[state] session.create 失败")
  }
  let cfg = ob()
    .b("deterministic", true)
    .n("max_steps", 10000000)
    .n("call_depth_limit", 10000)
    .n("quarantine_budget", 262144)
  if preset != "default" {
    ignore(cfg.s("preset", preset))
  }
  match entry_call(e, "config.set", cfg.done()) {
    Ok(_) => ()
    Err(m) => return Err(m)
  }
  let cp = if files.length() > 0 {
    ob().a("files", files).done()
  } else {
    ob().s("source", source).done()
  }
  entry_call(e, "compile", cp)
}

///|
/// 输出通道全量回读（stdout/stderr 的 delta 为 Latin-1 逐字节折回 String——
/// 字节域；此处折回 Bytes 后 UTF-8 解码回原文，消费方契约见 serve_io 头注）。
fn read_output(e : Entry, stream : String) -> String {
  let buf : Array[Byte] = []
  let mut cursor = 0
  let mut guard_n = 0
  while guard_n < 4096 {
    guard_n += 1
    let r = match
      entry_call(
        e,
        "output.delta",
        ob().n("cursor", cursor).s("stream", stream).done(),
      ) {
      Ok(v) => v
      Err(_) => break
    }
    let delta = jstr_or(jget(r, "delta"), "")
    for i = 0; i < delta.length(); i = i + 1 {
      buf.push((delta[i].to_int() & 0xFF).to_byte())
    }
    let next = jint_or(jget(r, "cursor"), cursor)
    let total = jint_or(jget(r, "total"), 0)
    if delta.length() == 0 || next >= total {
      break
    }
    cursor = next
  }
  let bytes = Bytes::from_array(buf)
  @util.utf8_text_partial(bytes)
}
