// cmd/lib/cli·引擎通道注入（main.js 退役批，2026-10-16）：lib/cli 的
// 引擎调用面收口为 EngineChannel——native/js 壳缺省走 direct_channel
//（gateway 库函数直连，行为零变化）；wasm 壳（cmd/vitro_wasm）注入
// gateway wasm 产物的 invoke 导出（extern "js" 胶水——产物只导出
// invoke/reset/protocol_version/engine_version 四函数，语义与库函数
// 同签名同源）。**vitro_wasm 禁止 import gateway**（会把整引擎编进 js
// 产物、wasm.wasm 就不是被测物了）——本 channel 是 wasm 臂复用单源壳
// 的唯一通道。
//
// set_clock / set_include_reader 在 wasm 形态无对应导出（gateway wasm
// 外壳 F-5 四导出面）——wasm 臂注 no-op：墙钟恒 0（main.js 既有形态，
// time() 输出本就分臂登记）、quote-include 走 compile{files} 多文件
// 通道（compile_params 分叉点）。

///|
/// 引擎通道（invoke NDJSON 单口 + 会话周边三口 + compile 参数装配）。
pub(all) struct EngineChannel {
  /// 单行请求 → 响应串（gateway.invoke / wasm 产物 invoke 导出同签名）。
  invoke : (String) -> String
  /// invoke + JSON 解析组合（gateway.invoke_parsed 同源形态）。
  invoke_parsed : (String) -> Json?
  /// 会话重置（R3 语义——保留会话级配置）。
  reset : () -> Unit
  /// 墙钟注入（wasm 形态 no-op——恒 0 语义分臂登记）。
  set_clock : (() -> UInt64) -> Unit
  /// quote-include 文件读取注册（wasm 形态 no-op——走 files 通道）。
  set_include_reader : ((String) -> String?) -> Unit
  /// compile params 装配（(file, src) → params JSON）。直连臂 = source+
  /// filename 形态（include_reader 已注册）；wasm 臂 = files 多文件形态
  ///（collect 主文件 + quote-include 递归——main.js collectFiles 同语义）。
  compile_params : (String, String) -> String
}
