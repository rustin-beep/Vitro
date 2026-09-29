// gateway 核心（S7 批五号，2026-09-29）：NDJSON 帧协议的 4 函数导出面
// （F-5 裁定）——invoke 单口承载 21 方法表，session 全局单例（单活跃
// 会话语义 D2，与 cmd/serve 进程模型同构）。
// 宿主契约（Node/浏览器）：
//   const mod = new WebAssembly.Module(buf,
//     { builtins: ['js-string'], importedStringConstants: '_' });
//   const inst = await WebAssembly.instantiate(mod, {});
//   inst.exports.invoke(line)  // String → String 直传（js-string builtins）
// shutdown 语义：invoke 返回的响应帧携带 "shutdown":true 时宿主自行停
// 止发下一行（无 stdio 循环的等价物——cmd/serve 壳同判据）。
// engine_version 分叉登记：F-5 语义含构建期 git 短哈希（产物自检），
// MoonBit 无编译期注入通道（数据装载选型裁定——大数据进源码同为人工
// 维护）——v1 为手维护版本常量，随发版更新；构建自检由 mooncakes 版本
// 承担（capabilities 的 engine_version 分叉同源，已在 CHANGELOG 登记）。

///|
/// 引擎版本常量（发版批随 moon.mod 版本连坐更新——0.7.0 首值）。
pub const ENGINE_VERSION : String = "0.7.0"

///|
/// 会话全局单例（模块级——一实例一引擎，多实例由宿主起多模块实例承担，
// 浏览器 Worker 多实例先例同理）。
let session : @session.Session = @session.Session::new()

///|
/// 单行请求 → 响应串（NDJSON 帧；未知方法回 protocol 错误帧——读不懂
/// 的请求必须报错，协议演化纪律 ②）。
#export_name("invoke")
pub fn invoke(line : String) -> String {
  serve_handle(session, line).0
}

///|
/// 会话重置（R3 语义：清空编译/运行态，保留会话级配置——与
/// session.reset 方法同语义，供宿主在无方法帧场景下直调）。
#export_name("reset")
pub fn reset() -> Unit {
  reset_session_preserving_config(session)
}

///|
/// 协议版本（StepPayload schema 轨道——与 capabilities.schema.version
/// 同单源 @protocol.SCHEMA_VERSION）。
#export_name("protocol_version")
pub fn protocol_version() -> String {
  @protocol.SCHEMA_VERSION
}

///|
/// 引擎版本（手维护常量——见文件头分叉登记）。
#export_name("engine_version")
pub fn engine_version() -> String {
  ENGINE_VERSION
}
