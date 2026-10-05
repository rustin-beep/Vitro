// cmd/vitro：CLI 总入口（#37 批②）——`vitro <cmd> [args]` 分派三 lib。
// argv 偏移约定（#37 v3）：cli_main 收**已剥子命令名**的参数
// （args[2:]——薄壳形态是 args[1:]，两形态对 lib 零差异）。
// 进程退出码 = 子命令退出码透传（全表见各 lib 头注）；未知命令 = 4。

///|
fn main {
  // quote-include 的文件系统读取注册（BUG-A 修复连坐，2026-10-05）：
  // gateway 经 include_reader 分叉——未注册则 compile 帧词法走 vfs 空表，
  // quote-include 恒 E1021；run 文本模式不走 gateway（compile_and_report
  // 直连 FsProvider）不受影响，--json / step / api 的 compile 帧在
  // gateway 侧词法，CLI 进程必须注册（cmd/serve 同款）
  @gateway.set_include_reader(fn(path : String) -> String? {
    let s = @fs.read_file_to_string(path) catch { _ => return None }
    Some(s)
  })
  let args = @env.args()
  if args.length() < 2 {
    print_help()
    c_exit(4)
  }
  let cmd = args[1]
  let rest : Array[String] = []
  for i = 2; i < args.length(); i = i + 1 {
    rest.push(args[i])
  }
  let code = match cmd {
    "run" => @cli.run(rest, make_clock(), make_stdin(), write_stdout_stub)
    "compile" => @cli.compile(rest, make_stdin())
    "step" => @cli.step(rest, make_stdin())
    "api" => @cli.api(rest, make_stdin())
    "serve" | "dump-tokens" | "dump-ast" | "dump-typeck" | "dump-compile" => {
      println(
        "vitro: '\{cmd}' 走独立 exe（moonbit/_build/native/release/build/cmd/<name>/——防线调用面，暂不收拢；见 issue #37 B1）；一次性脚本化用 'vitro api <method> <params>' 覆盖全部协议方法",
      )
      4
    }
    "help" | "--help" | "-h" => {
      print_help()
      0
    }
    _ => {
      println("vitro: 未知命令 '\{cmd}'")
      print_help()
      4
    }
  }
  c_exit(code)
}

///|
fn print_help() -> Unit {
  println("用法: vitro <cmd> [args]")
  println(
    "  run <file.c> [--dump-memory out] [-i in] [-- <argv...>]   编译+执行（退出码 0/1/2/3/4）",
  )
  println(
    "  compile <file.c | -> [--json]                             编译+诊断单出",
  )
  println(
    "  step <file.c | -> [--max-steps N] [--json|--summary]      一次性 step 流（交互调试走 serve）",
  )
  println(
    "  api <method> [params-json] | api --batch < frames.ndjson  万能单帧 + 批式多帧（状态跨帧保留——seek/breakpoints/input.feed 序列可脚本化；响应 NDJSON 直出；任一帧 ok:false → rc=1）",
  )
  println(
    "  help                                                      本帮助",
  )
}

///|
extern "C" fn c_exit(code : Int) -> Unit = "exit"

///|
/// stdout 字节直写（stdout_stub.c 注入——≥0x80 字节原样落盘，绕开
/// println 的 UTF-8 出口编码；DIFF-EXIT-STDOUT-ENCODE-01 销案接线）
#borrow(b)
extern "C" fn write_stdout_stub(b : Bytes) -> Unit = "moonbit_vitro_write_stdout"

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
