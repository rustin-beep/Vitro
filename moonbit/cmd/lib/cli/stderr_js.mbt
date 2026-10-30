// cli_stderr_write 的 js 绑定（#129 通道分立批）：node 的 stderr 同步
// 直写（Buffer.from(Bytes)——MoonBit js 后端 Bytes = Uint8Array）。
// #366 同族治本（PR #367 审阅 P2-3，2026-10-28）：process.stderr.write
// 对**管道**是异步写、帧后立即 process.exit 丢弃未刷写队列。实测分界
// = **单次写大小 vs 管道缓冲（64KB）**：say 的小段多写（编译错风暴
// 500 段×~150B，总量 74KB）管道口径完整；**单段 >64KB**（超长标识符
// 诊断 70106B）截断于 65536B（WSL 实测）。改 fs.writeSync(2, …) 同步
// 写，与 stdout 侧 out_line/js_write_stdout 出口原语同款（fd=2）——
// 单段大小不再受管道缓冲约束。native 臂 stderr_stub.c fwrite + CRT
// exit 刷缓冲不受影响。

///|
extern "js" fn cli_stderr_write(b : Bytes) -> Unit =
  #| function(b) {
  #|   process.getBuiltinModule("fs").writeSync(2, Buffer.from(b));
  #| }
