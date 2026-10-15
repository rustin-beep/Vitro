// js 入口薄壳：IO 全走 extern "js"（node），逻辑全在 cmd/lib/cli 单源。
// 子命令分派与 cmd/vitro（native）**整表同构**（审阅 P1-②：原只 4 臂，
// serve/dump 族/help/--help/-h 全落未知命令——新入口分派表与老入口
// 不同构即 C5 形态）；差异仅在 IO 绑定（exit/argv/stdin/stdout）。

///|
fn main {
  let args = js_args()
  if args.length() < 1 {
    print_help()
    js_exit(4)
  }
  let cmd = args[0]
  let rest : Array[String] = []
  for i = 1; i < args.length(); i = i + 1 {
    rest.push(args[i])
  }
  let code = match cmd {
    "run" => @cli.run(rest, js_clock_millis, js_read_stdin, js_write_stdout)
    "compile" => @cli.compile(rest, js_read_stdin)
    "step" => @cli.step(rest, js_read_stdin, js_write_stdout)
    "api" => @cli.api(rest, js_read_stdin)
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
  js_exit(code)
}

///|
fn print_help() -> Unit {
  println("用法: vitro <cmd> [args]")
  println(
    "  run <file.c> [--json] [--dump-memory out] [-i in] [-- <argv...>]   编译+执行（退出码 0/1/2/3/4；--json=事件流 NDJSON）",
  )
  println(
    "  compile <file.c | -> [--json]                             编译+诊断单出",
  )
  println(
    "  step <file.c | -> [--max-steps N] [--json|--summary]      一次性 step 流（交互调试走 serve）",
  )
  println(
    "  api <method> [params-json] | api --batch < frames.ndjson  万能单帧 + 批式多帧（状态跨帧保留——seek/breakpoints/input.feed 序列可脚本化；响应 NDJSON 直出；任一帧 ok:false → rc=1；api help <method> 看参数详情）",
  )
  println(
    "  help                                                      本帮助",
  )
}

///|
extern "js" fn js_args() -> Array[String] =
  #| function() {
  #| return process.argv.slice(2);
  #| }

///|
extern "js" fn js_clock_millis() -> UInt64 =
  #| function() {
  #| return BigInt(Date.now());
  #| }

///|
extern "js" fn js_read_stdin() -> Bytes =
  #| function() {
  #| const all = process.getBuiltinModule("fs").readFileSync(0);
  #| const bytes = new Uint8Array(all.length);
  #| bytes.set(all);
  #| return bytes;
  #| }

///|
extern "js" fn js_write_stdout(b : Bytes) -> Unit =
  #| function(b) {
  #| process.getBuiltinModule("fs").writeSync(1, Buffer.from(b));
  #| }

///|
extern "js" fn js_exit(code : Int32) -> Unit =
  #| function(code) {
  #| process.exit(code);
  #| }
