// cmd/vitro：CLI 总入口（#37 批②）——`vitro <cmd> [args]` 分派三 lib。
// argv 偏移约定（#37 v3）：cli_main 收**已剥子命令名**的参数
// （args[2:]——薄壳形态是 args[1:]，两形态对 lib 零差异）。
// 进程退出码 = 子命令退出码透传（全表见各 lib 头注）；未知命令 = 4。

///|
fn main {
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
    "run" => @cli.run(rest, make_clock(), make_stdin())
    "compile" => @cli.compile(rest, make_stdin())
    "step" => @cli.step(rest, make_stdin())
    "serve" | "dump-tokens" | "dump-ast" | "dump-typeck" | "dump-compile" => {
      println(
        "vitro: '\{cmd}' 走独立 exe（moonbit/_build/native/release/build/cmd/<name>/——防线调用面，暂不收拢；见 issue #37 B1）",
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
    "  compile <file.c>                                          编译+诊断单出",
  )
  println(
    "  step <file.c> [--max-steps N] [--json|--summary]          一次性 step 流（交互调试走 serve）",
  )
  println(
    "  help                                                      本帮助",
  )
}

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
