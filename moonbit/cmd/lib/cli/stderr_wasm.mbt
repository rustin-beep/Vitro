// cli_stderr_write 的 wasm 目标占位（#129 通道分立批）：CLI 壳只有 js/
// native 目标（cmd/vitro_wasm 与 cmd/vitro_js 均 +js、native 壳 native）
// ——本目标无文本面消费者。fail loud 占位防误接（若未来 wasm-gc 壳需
// 要 stderr，补宿主 import 通道后再实现）。

///|
fn cli_stderr_write(_b : Bytes) -> Unit {
  fail(
    "cli_stderr_write: wasm 目标无 stderr 通道（CLI 壳不编译该目标）",
  )
}
