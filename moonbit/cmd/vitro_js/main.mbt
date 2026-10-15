// js 入口薄壳：IO 全走 extern "js"（node），逻辑全在 cmd/lib/cli 单源。
// 子命令分派与 cmd/vitro（native）同表——argv 偏移：js_args 已剥 node 自身
// 与脚本路径，args[0] = 子命令名。

///|
fn main {
  let args = js_args()
  if args.length() < 1 {
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
    _ => {
      println("vitro: 未知命令 '\{cmd}'")
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
