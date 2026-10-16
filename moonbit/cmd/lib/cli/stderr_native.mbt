// cli_stderr_write 的 native 绑定（#129 通道分立批）：stub = 本目录
// stderr_stub.c（moon.pkg native-stub 挂载）。

///|
#borrow(b)
extern "C" fn cli_stderr_write(b : Bytes) -> Unit = "moonbit_vitro_cli_write_stderr"
