// cmd/vitro：CLI 总入口（#37 批②）——`vitro <cmd> [args]` 分派三 lib。
// argv 偏移约定（#37 v3）：cli_main 收**已剥子命令名**的参数
// （args[2:]——薄壳形态是 args[1:]，两形态对 lib 零差异）。
// 进程退出码 = 子命令退出码透传（全表见各 lib 头注）；未知命令 = 4。

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
  if args.length() < 2 {
    @cli.print_usage(true) // #215：无参用法错（rc=4）走 stderr
    c_exit(4)
  }
  let cmd = args[1]
  let rest : Array[String] = []
  for i = 2; i < args.length(); i = i + 1 {
    rest.push(args[i])
  }
  let code = match cmd {
    "run" =>
      @cli.run(
        rest,
        make_clock(),
        make_stdin(),
        write_stdout_stub,
        channel=@engine_direct.direct_channel(),
      )
    "compile" =>
      @cli.compile(rest, make_stdin(), channel=@engine_direct.direct_channel())
    "step" =>
      @cli.step(
        rest,
        make_stdin(),
        write_stdout_stub,
        channel=@engine_direct.direct_channel(),
      )
    "api" =>
      @cli.api(
        rest,
        make_stdin(),
        write_stdout=write_stdout_stub,
        channel=@engine_direct.direct_channel(),
      )
    "serve" | "dump-tokens" | "dump-ast" | "dump-typeck" | "dump-compile" => {
      // #215：rc=4 用法错语境的指引走 stderr（stdout 恒空不变式）
      @cli.usage_err(
        "vitro: '\{cmd}' 走独立 exe（moonbit/_build/native/release/build/cmd/<name>/——防线调用面，暂不收拢；见 issue #37 B1）；一次性脚本化用 'vitro api <method> <params>' 覆盖全部协议方法",
      )
      4
    }
    "help" | "--help" | "-h" => {
      @cli.print_usage(false)
      0
    }
    _ => {
      @cli.usage_err("vitro: 未知命令 '\{cmd}'")
      @cli.print_usage(true)
      4
    }
  }
  c_exit(code)
}

///|
extern "C" fn c_exit(code : Int32) -> Unit = "exit"

///|
/// stdout 字节直写（stdout_stub.c 注入——≥0x80 字节原样落盘，绕开
/// println 的 UTF-8 出口编码；DIFF-EXIT-STDOUT-ENCODE-01 销案接线）
#borrow(b)
extern "C" fn write_stdout_stub(b : Bytes) -> Unit = "moonbit_vitro_write_stdout"

///|
extern "C" fn clock_secs_stub() -> Int32 = "moonbit_vitro_clock_secs"

///|
extern "C" fn clock_millis_frac_stub() -> Int32 = "moonbit_vitro_clock_millis_frac"

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
