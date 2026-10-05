// cmd/run：CLI `run` 薄壳（#37 批②）——逻辑在 cmd/lib/run（下沉纪律：
// main 包 import main 包是工具链 warning 态）。进程退出码全表见 lib 注释；
// cli_main 的 args 约定 = 已剥程序名（薄壳形态，无子命令名）。

///|
fn main {
  let args = @env.args()
  let rest : Array[String] = []
  for i = 1; i < args.length(); i = i + 1 {
    rest.push(args[i])
  }
  c_exit(@cli.run(rest, make_clock(), make_stdin(), write_stdout_stub))
}

///|
/// stdout 字节直写（stdout_stub.c 注入——≥0x80 字节原样落盘，绕开
/// println 的 UTF-8 出口编码；DIFF-EXIT-STDOUT-ENCODE-01 销案接线）
#borrow(b)
extern "C" fn write_stdout_stub(b : Bytes) -> Unit = "moonbit_vitro_write_stdout"

///|
extern "C" fn c_exit(code : Int) -> Unit = "exit"

///|
extern "C" fn clock_secs_stub() -> Int = "moonbit_vitro_clock_secs"

///|
extern "C" fn clock_millis_frac_stub() -> Int = "moonbit_vitro_clock_millis_frac"

///|
fn make_clock() -> () -> UInt64 {
  fn() {
    clock_secs_stub().to_uint64() * 1000UL +
    clock_millis_frac_stub().to_uint64()
  }
}

///|
extern "C" fn read_stdin_bytes() -> Bytes = "moonbit_vitro_read_stdin_bytes"

///|
fn make_stdin() -> () -> Bytes {
  fn() { read_stdin_bytes() }
}
