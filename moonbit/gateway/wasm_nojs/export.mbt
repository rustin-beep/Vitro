// 4 函数导出面（F-5）：转发到 gateway 本体——外壳零逻辑（拆包配方：
// 本包只持 #export_name 面，改协议语义请动 gateway，勿在此加实现）。

///|
/// 单行请求 → 响应串（NDJSON 帧；详见 gateway 本体 invoke 注释）。
#export_name("invoke")
pub fn invoke(line : String) -> String {
  @gateway.invoke(line)
}

///|
/// 会话重置（R3 语义——详见 gateway 本体 reset 注释）。
#export_name("reset")
pub fn reset() -> Unit {
  @gateway.reset()
}

///|
/// 协议版本（protocol 包 SCHEMA_VERSION 单源）。
#export_name("protocol_version")
pub fn protocol_version() -> String {
  @gateway.protocol_version()
}

///|
/// 引擎版本（gateway 本体 ENGINE_VERSION 手维护常量）。
#export_name("engine_version")
pub fn engine_version() -> String {
  @gateway.engine_version()
}

// ── 对拍桥接（#199 五方批，2026-10-20）：全 i32 参数面，GC ref 不跨边界 ──
// wasmtime 等宿主无法构造 (ref (array (mut i16))) 参数；桥接把 invoke 的
// String 往返拆成 write(累积请求) → invoke(执行，返回响应长度) →
// read(按下标取响应 code unit)。仅存在于零导入风味，不进 JS 风味产物。

///|
let bridge_req : StringBuilder = StringBuilder::new()

///|
let bridge_resp : StringBuilder = StringBuilder::new()

///|
#export_name("bridge_write")
pub fn bridge_write(unit : Int32) -> Unit {
  bridge_req.write_char(Char::from_int(unit))
}

///|
#export_name("bridge_invoke")
pub fn bridge_invoke() -> Int32 {
  let req = bridge_req.to_string()
  bridge_req.reset()
  let resp = invoke(req)
  bridge_resp.reset()
  bridge_resp.write_string(resp)
  resp.length()
}

///|
#export_name("bridge_read")
pub fn bridge_read(idx : Int32) -> Int32 {
  bridge_resp.to_string().code_units()[idx].to_int()
}
