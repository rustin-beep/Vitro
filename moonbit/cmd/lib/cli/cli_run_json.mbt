// run --json 事件流（#37 批③）：单一 NDJSON 流走 stdout——每行
// `{"type":...,"frame":<gateway 帧>}`，帧单源（gateway.invoke 协议即真源，
// 与 demo/serve 同一通道——零手拼诊断）。程序原样输出留给文本模式
//（标记行协议可管道解析）；agent 拿结构化、shell 管道拿原文，两模式各取所需。
// 退出码与文本模式同表（diag 失败=1 / trap=2 / 步数超限=3 / 正常=0）。
// 参数面与文本模式同构（2026-10-04 用户性能实测抓到 -i/--argv 静默丢——
// 扩参：argv 进 run 帧；-i 在 waiting_input 时 input.feed 续跑后重拉输出；
// --dump-memory 在 --json 下不适用（协议无 1MB 映像导出面——spec §3 登记））。

///|
fn json_event_stream(
  src : String,
  file : String,
  stdin_file : String,
  argv : Array[String],
) -> Int {
  let mut id = 0
  let inv = fn(method : String, params : String) -> String {
    id += 1
    @gateway.invoke(
      "{\"id\":\{id},\"method\":\"\{method}\",\"params\":\{params}}",
    )
  }
  @gateway.reset()
  ignore(inv("session.create", "{}"))
  ignore(
    inv(
      "config.set", "{\"max_steps\":10000000,\"call_depth_limit\":10000,\"deterministic\":true,\"quarantine_budget\":262144}",
    ),
  )
  let comp = inv("compile", "{\"source\":\"\{escape_json(src)}\"}")
  println("{\"type\":\"diag\",\"frame\":\{comp}}")
  if comp.contains("\"ok\":false") {
    return 1
  }
  // argv 透传（gateway 语义：argv 数组 = **完整 argv 含 argv[0]**
  //（cases.js 先例 ["prog","hello-arg"]）——与文本管线 argv_full 同构：
  // [源文件路径, ...透传]）
  let argv_json = if argv.length() > 0 {
    let items = StringBuilder()
    items.write_string("\"\{escape_json(file)}\"")
    for i = 0; i < argv.length(); i = i + 1 {
      items.write_string(",\"\{escape_json(argv[i])}\"")
    }
    "{\"argv\":[\{items.to_string()}]}"
  } else {
    "{}"
  }
  let mut run = inv("run", argv_json)
  // -i 批注入等价：waiting 时 input.feed——**feed 的响应帧即续跑结果**
  //（demo run.ts feedStdin 同款协议语义，非再发 run）
  if run.contains("\"waiting_input\":true") && stdin_file != "" {
    let mut text = @fs.read_file_to_string(stdin_file) catch { _ => "" }
    if !text.has_suffix("\n") {
      text = text + "\n"
    }
    if text != "\n" {
      run = inv("input.feed", "{\"text\":\"\{escape_json(text)}\"}")
    }
  }
  println("{\"type\":\"run\",\"frame\":\{run}}")
  let out = inv("output.delta", "{\"cursor\":0,\"stream\":\"stdout\"}")
  println("{\"type\":\"stdout\",\"frame\":\{out}}")
  // 退出码与 run 帧 status 对齐（文本模式判 vm 事实——json 模式帧字段）
  if run.contains("\"status\":\"trap\"") {
    if run.contains("步数") {
      return 3
    }
    return 2
  }
  0
}
