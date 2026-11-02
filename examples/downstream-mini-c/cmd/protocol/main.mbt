// 形态 B：下游直连 gateway 协议层——`@gateway.invoke(String) -> String`，
// 一行 NDJSON 请求进、一行响应出；状态跨帧保留（同一会话）。
//
// 协议面权威 = 随包分发的 .mooncakes/vitro/engine/docs/spec/CLI_PROTOCOL_V1.md
// 与 STEP_PAYLOAD_SCHEMA_V0_1.md；方法清单可用仓内 CLI `vitro api help` 查。
// 0.9.1 发布包内 gateway **无** pkg.generated.mbti（R3 实测只能 grep 源码找
// 签名）——B3 批（2026-11-02）已在仓内补齐（gateway 增 wasm 目标使 moon info
// 落盘），随下一版本发布进包；在此之前签名以本文件调用形态为准。
//
// 运行（本目录）：moon run --target js cmd/protocol
//（默认 wasm 目标与 gateway 的 supported_targets 不交，见 moon.pkg 注）。

///|
fn main {
  println("engine_version:   \{@gateway.engine_version()}")
  println("protocol_version: \{@gateway.protocol_version()}")
  // reset = 清会话态（进程内 gateway 是单例会话；多次 main 级运行前先 reset）
  @gateway.reset()
  let inv = fn(method_name : String, params : String) -> String {
    @gateway.invoke(
      "{\"id\":1,\"method\":\"\{method_name}\",\"params\":\{params}}",
    )
  }
  println("[session.create] \{inv("session.create", "{}")}")
  let src = "int main(void) {\n  int i;\n  int s = 0;\n  for (i = 0; i < 5; i = i + 1) { s = s + i; }\n  printf(\"sum=%d\\n\", s);\n  return 0;\n}\n"
  // 源码进 JSON 字符串域：用引擎自带的 json_escape（RFC 8259 全量控制字符
  // \u00XX、serde_json 口径）——不必手写转义。
  let comp = inv(
    "compile",
    "{\"source\":\"\{@util.json_escape(src)}\",\"filename\":\"main.c\"}",
  )
  println("[compile] \{comp}")
  guard !comp.contains("\"ok\":false") else {
    println(
      "编译失败，终止（诊断在 compile 帧的 result.diagnostics）",
    )
    return
  }
  // run 帧的 argv 恒下发（argv[0]=程序名）——gateway 默认 [] 会让 argv[0]
  // 解引用 NULL trap（仓内 cli_step 同款注记）。
  println("[run] \{inv("run", "{\"argv\":[\"main.c\"]}")}")
  println("[step.begin] \{inv("step.begin", "{}")}")
  // step.next 收帧循环——终态三标记 finished / trapped / waiting_input 之一
  // 必居其一；上限 200 批是本示例的防御（引擎有 max_steps 预算墙兜底）。
  let mut batches = 0
  let mut last_head = ""
  while batches < 200 {
    let r = inv("step.next", "{}")
    batches = batches + 1
    if r.contains("\"finished\":true") ||
      r.contains("\"trapped\":true") ||
      r.contains("\"waiting_input\":true") {
      last_head = if r.length() > 160 { r[:160].to_owned() + "..." } else { r }
      break
    }
  }
  println("[step.next] 共 \{batches} 批，终帧: \{last_head}")
  // 程序 stdout：output.delta 分页游标（cursor 从 0 起；delta 为 Latin-1 折回
  // 文本——字节 0x80–0xFF 逐字节映射为同码点字符，消费方按需反折回字节域）
  println(
    "[output.delta stdout] \{inv("output.delta", "{\"cursor\":0,\"stream\":\"stdout\"}")}",
  )
  println("[session.destroy] \{inv("session.destroy", "{}")}")
}
