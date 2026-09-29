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
