// cli_stderr_write 的 js 绑定（#129 通道分立批）：node 的 process.stderr
// 直写（Buffer.from(Bytes)——MoonBit js 后端 Bytes = Uint8Array）。

///|
extern "js" fn cli_stderr_write(b : Bytes) -> Unit =
  #| function(b) {
  #|   process.stderr.write(Buffer.from(b));
  #| }
