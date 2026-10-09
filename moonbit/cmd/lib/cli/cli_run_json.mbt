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
  let inv = fn(method_name : String, params : String) -> String {
    id += 1
    @gateway.invoke(
      "{\"id\":\{id},\"method\":\"\{method_name}\",\"params\":\{params}}",
    )
  }
  @gateway.reset()
  ignore(inv("session.create", "{}"))
  ignore(
    inv(
      "config.set", "{\"max_steps\":10000000,\"call_depth_limit\":10000,\"deterministic\":true,\"quarantine_budget\":262144}",
    ),
  )
  // filename 装配（BUG-A 修复，2026-10-05）：同 cli_compile——丢 filename
  // 则 base_dir 退化、同目录 include 断；stdin（"-"）不传
  let compile_params = if file == "-" {
    "{\"source\":\"\{escape_json(src)}\"}"
  } else {
    "{\"source\":\"\{escape_json(src)}\",\"filename\":\"\{escape_json(file)}\"}"
  }
  let comp = inv("compile", compile_params)
  println("{\"type\":\"diag\",\"frame\":\{comp}}")
  if comp.contains("\"ok\":false") {
    return 1
  }
  // argv **恒下发**（2026-10-04 二轮审 P1-A 修正：gateway 语义 = argv 数组为
  // 完整 argv 含 argv[0]——零透传时也须发 [源文件路径]，否则 gateway 侧
  // runtime_argv 保持会话默认 []（argc=0、argv[0] 解引用 NULL trap、堆起点
  // 不上移）；初版 else "{}" 丢整段，自验样本只落在「有透传」形态漏掉零参）
  let items = StringBuilder()
  items.write_string("\"\{escape_json(file)}\"")
  for i = 0; i < argv.length(); i = i + 1 {
    items.write_string(",\"\{escape_json(argv[i])}\"")
  }
  let argv_json = "\"argv\":[\{items.to_string()}]"
  // -i 批注入（2026-10-04 二轮审 P1-B 修正：与文本模式**同构**走
  // run{input, batch_input:true}——批注入耗尽即 EOF；初版 input.feed 单次
  // 喂在多行 scanf 循环下仍 waiting（feed 不置 batch 态），输出静默丢）
  let input_json = if stdin_file != "" {
    let mut text = @fs.read_file_to_string(stdin_file) catch { _ => "" }
    if !text.has_suffix("\n") {
      text = text + "\n"
    }
    ",\"input\":\"\{escape_json(text)}\",\"batch_input\":true"
  } else {
    ""
  }
  let run = inv("run", "{\{argv_json}\{input_json}}")
  println("{\"type\":\"run\",\"frame\":\{run}}")
  let out = inv("output.delta", "{\"cursor\":0,\"stream\":\"stdout\"}")
  println("{\"type\":\"stdout\",\"frame\":\{out}}")
  // note 通道（2026-10-04 二轮审 P2：完成附注 + 泄漏报告——gateway 侧
  // serve_run 已合成 note，CLI 此前只拉 stdout 致整段丢失）
  let note = inv("output.delta", "{\"cursor\":0,\"stream\":\"note\"}")
  println("{\"type\":\"note\",\"frame\":\{note}}")
  // 退出码与 run 帧 status 对齐（文本模式判 vm 事实——json 模式帧字段）。
  // 超限判定=结构化 steps_executed（2026-10-04 审阅 P3 统一：实测超限时
  // steps_executed 恰等 max_steps〔到达即停〕——值判免教学文案变更脆；
  // cli 侧 max_steps 即本函数 config.set 写入值 10000000）
  if run.contains("\"status\":\"trap\"") {
    if run.contains("\"steps_executed\":10000000") {
      return 3
    }
    return 2
  }
  0
}
