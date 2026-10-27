// cmd/step 薄壳——逻辑在 cmd/lib/step。

///|
/// #335（2026-10-27）：帧通道行尾治本——main 首行前置调用（stdout/stderr
/// 双 fd 切二进制，Windows CRT 文本模式对 println 帧通道的换行改写
/// （CRLF）消除；stub 见 stdout_stub.c 文件头）。
extern "C" fn ensure_binary_mode_stub() -> Unit = "moonbit_vitro_ensure_binary_mode"

///|
fn main {
  ensure_binary_mode_stub()
  @content_data.install_baked() // #130 批③a：烘焙教学表装载（lean 拆包后引擎默认空表）
  let args = @env.args()
  let rest : Array[String] = []
  for i = 1; i < args.length(); i = i + 1 {
    rest.push(args[i])
  }
  c_exit(
    @cli.step(
      rest,
      make_stdin(),
      write_stdout_stub,
      channel=@engine_direct.direct_channel(),
    ),
  )
}

///|
/// stdout 字节直写（stdout_stub.c 注入——≥0x80 字节原样落盘，绕开
/// println 的 UTF-8 出口编码；run 壳同款。#57-1：step 文本模式透出程序
/// stdout 时接入）
#borrow(b)
extern "C" fn write_stdout_stub(b : Bytes) -> Unit = "moonbit_vitro_write_stdout"

///|
extern "C" fn c_exit(code : Int32) -> Unit = "exit"

///|
extern "C" fn read_stdin_bytes() -> Bytes = "moonbit_vitro_read_stdin_bytes"

///|
fn make_stdin() -> () -> Bytes {
  fn() { read_stdin_bytes() }
}
