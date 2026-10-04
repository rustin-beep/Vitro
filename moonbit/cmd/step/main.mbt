// cmd/step 薄壳——逻辑在 cmd/lib/step。

///|
fn main {
  let args = @env.args()
  let rest : Array[String] = []
  for i = 1; i < args.length(); i = i + 1 {
    rest.push(args[i])
  }
  c_exit(@cli.step(rest, make_stdin()))
}

///|
extern "C" fn c_exit(code : Int) -> Unit = "exit"

///|
extern "C" fn read_stdin_bytes() -> Bytes = "moonbit_vitro_read_stdin_bytes"

///|
fn make_stdin() -> () -> Bytes {
  fn() { read_stdin_bytes() }
}
