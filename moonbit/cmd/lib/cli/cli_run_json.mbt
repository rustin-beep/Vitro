// run --json 事件流（#37 批③）：单一 NDJSON 流走 stdout——每行
// `{"type":...,"frame":<gateway 帧>}`，帧单源（gateway.invoke 协议即真源，
// 与 demo/serve 同一通道——零手拼诊断）。程序原样输出留给文本模式
//（标记行协议可管道解析）；agent 拿结构化、shell 管道拿原文，两模式各取所需。
// 退出码与文本模式同表（diag 失败=1 / trap=2 / 步数超限=3 / 正常=0）。

///|
fn json_event_stream(src : String) -> Int {
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
  let run = inv("run", "{}")
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
