// js 入口薄壳：IO 全走 extern "js"（node），逻辑全在 cmd/lib/cli 单源。
// 子命令分派与 cmd/vitro（native）**整表同构**（审阅 P1-②：原只 4 臂，
// serve/dump 族/help/--help/-h 全落未知命令——新入口分派表与老入口
// 不同构即 C5 形态）；差异仅在 IO 绑定（exit/argv/stdin/stdout）。

///|
fn main {
  @content_data.install_baked() // #130 批③a：烘焙教学表装载（lean 拆包后引擎默认空表）
  let args = js_args()
  if args.length() < 1 {
    @cli.print_usage(true) // #215：无参用法错（rc=4）走 stderr
    js_exit(4)
  }
  let cmd = args[0]
  let rest : Array[String] = []
  let mut i = 1
  while i < args.length() {
    rest.push(args[i])
    i += 1
  }
  let code = match cmd {
    "run" =>
      @cli.run(
        rest,
        js_clock_millis,
        js_read_stdin,
        js_write_stdout,
        channel=@engine_direct.direct_channel(),
      )
    "compile" =>
      @cli.compile(rest, js_read_stdin, channel=@engine_direct.direct_channel())
    "step" =>
      @cli.step(
        rest,
        js_read_stdin,
        js_write_stdout,
        channel=@engine_direct.direct_channel(),
      )
    "api" =>
      @cli.api(rest, js_read_stdin, channel=@engine_direct.direct_channel())
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
  js_exit(code)
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
