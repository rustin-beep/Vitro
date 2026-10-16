// cmd/lib/cli：include reader 注册下沉（病 43 修复，#71 第二梯队
// 2026-10-11）。此前注册散在三壳（cmd/vitro、cmd/run、cmd/serve），薄壳
// cmd/compile 与 cmd/step 漏调 → quote-include 恒 E1021（spec「薄壳与
// 总入口逐字节一致」破坏；round6 定责的处方二：下沉进 lib 整体消灭
// 壳层注册义务——moon.pkg 已 import fs+gateway，零新依赖边）。
// serve 壳不经本包（独立 serve 通道），其自有注册保留。
//
// main.js 退役批（2026-10-16）：注册走 EngineChannel（wasm 臂 no-op——
// quote-include 走 compile{files} 通道，compile_params 分叉点）。

///|
/// quote-include 的文件系统读取注册（幂等——gateway 全局槽，重复设置
/// 同语义 reader 无害；四入口 run/compile/step/api 首行各调一次）。
/// 未注册时 gateway 侧词法走 vfs 空表 → quote-include 恒 E1021。
fn ensure_include_reader(channel : EngineChannel) -> Unit {
  (channel.set_include_reader)(fn(path : String) -> String? {
    let s = @fs.read_file_to_string(path) catch { _ => return None }
    Some(s)
  })
}
