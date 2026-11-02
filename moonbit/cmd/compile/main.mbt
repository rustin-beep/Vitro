// cmd/compile 薄壳——逻辑在 cmd/lib/compile（下沉纪律同 cmd/run）。

///|
/// #335 同款（B3 批 2026-11-02 补——M35 A6）：compile --json 的 diag 帧
/// 自此经 write_stdout 注入落 stdout，壳取得 stdout 物理输出面，行尾治本
/// 前置调用连坐（stdout/stderr 双 fd 切二进制；stub 见 stdout_stub.c 文件头，
/// 四副本逐字节同——single_source 闸 stdout_stub_copies 机判）。
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
    @cli.compile(
      rest,
      make_stdin(),
      write_stdout=write_stdout_stub,
      channel=@engine_direct.direct_channel(),
    ),
  )
}

///|
/// stdout 字节直写（stdout_stub.c 注入——≥0x80 字节原样落盘，绕开
/// println 的 UTF-8 出口编码；run/step 壳同款。B3 批：compile --json
/// diag 帧出口接入——旧形态 lib 内 drop_stdout 吞帧，失败/成功两路 stdout
/// 均 0 字节）
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
