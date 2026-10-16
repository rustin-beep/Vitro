// cli_stderr_write 的 wasm 目标实现（#129 通道分立批；CI 红实锤修
// 2026-10-16）：CLI 壳只有 js/native 目标（cmd/vitro_wasm 与
// cmd/vitro_js 均 +js、native 壳 native）——本目标无真实消费者，但
// **moon test 四目标全包编译**使 wbtest 在 wasm-gc 下可达 say()（用法
// 错路径）：abort 形态直接炸测试（b87 锚实锤）、fail() 要求 error 签名
// 传染。降级 println——语义不完美（wasm-gc 无 stderr 宿主通道），但
// 该目标无 CLI 出口，此路径只有测试基建会踩。

///|
fn cli_stderr_write(b : Bytes) -> Unit {
  println(b)
}
