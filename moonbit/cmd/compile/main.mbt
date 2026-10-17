// cmd/compile 薄壳——逻辑在 cmd/lib/compile（下沉纪律同 cmd/run）。

///|
fn main {
  @content_data.install_baked() // #130 批③a：烘焙教学表装载（lean 拆包后引擎默认空表）
  let args = @env.args()
  let rest : Array[String] = []
  for i = 1; i < args.length(); i = i + 1 {
    rest.push(args[i])
  }
  c_exit(
    @cli.compile(rest, make_stdin(), channel=@engine_direct.direct_channel()),
  )
}

///|
extern "C" fn c_exit(code : Int32) -> Unit = "exit"

///|
extern "C" fn read_stdin_bytes() -> Bytes = "moonbit_vitro_read_stdin_bytes"

///|
fn make_stdin() -> () -> Bytes {
  fn() { read_stdin_bytes() }
}
