// #70 第二步（2026-10-11）：gateway 帧单源管线——run/compile 两子命令的
// json 模式（NDJSON 事件流）与文本模式（帧→标记行渲染）共用同一 invoke
// 序列。旧 compile_and_report 直调管线（lexer→parser→typeck→codegen 手拼
// + println）拆除：诊断出口从此单源（#64「双臂不对账」的病根——同一
// codegen 失败 exe 打印 / gateway 吞诊断——两出口自此同帧同渲染）。
//
// 文本模式契约（逐字节对齐拆除前行形态——vm_diff/clang_direct 剥离器与
// 全量语料即锚）：`// COMPILE-ERROR|WARNING|HINT <code|codegen> <l>:<c> <msg>`
// + `// COMPILE-OK`；run 段 `// STDERR/NOTE/TRAP/EXIT` 行 + stdout 字节
// 直写（Latin-1 折回还原 + 尾换行保形，壳 writeStdoutBytes 同款）。
//
// 退出码与 json 模式同表（diag 失败=1 / trap=2 / 步数超限=3 / 正常=0）。

///|
/// core Json 访问窄面（cli 侧私有——gateway::invoke_parsed 的消费 helper）
fn jfield(v : Json, key : String) -> Json {
  match v {
    Object(m) =>
      match m.get(key) {
        Some(j) => j
        None => Json::null()
      }
    _ => Json::null()
  }
}

///|
fn jstr(v : Json) -> String {
  match v {
    String(s) => s
    _ => ""
  }
}

///|
fn jint(v : Json) -> Int {
  // 协议字段（line/column/return_value/steps_executed）恒整型——Double
  // 截断无损（域 < 2^31）；浮点形态按 0 兜底（协议破损，渲染层自然退化）
  match v {
    Number(n) => n.to_int()
    _ => 0
  }
}

///|
/// Latin-1 折回 delta → 原始字节（serve_io 头注分叉登记①的口径：stdout/
/// stderr 通道 delta 按字节折回 String——还原 = 每码点 & 0xFF 落字节）。
fn latin1_to_bytes(delta : String) -> Bytes {
  let out : Array[Byte] = Array(capacity=delta.length())
  for c in delta {
    out.push((Char::to_int(c) & 0xFF).to_byte())
  }
  Bytes::from_array(out)
}

///|
/// compile 帧诊断行渲染（返回 has_error——error 级存在即编译失败 rc=1）。
/// codegen 过渡码（E0/Unknown）渲染为 spec 在册无码形态（#70 第一步与壳
/// 同款）；其余按帧 code_str 原样（与拆除前 `E\{code}` / `W\{code}` 同形）。
fn render_diag_frame(frame : Json) -> Bool {
  let result = jfield(frame, "result")
  let mut has_error = false
  match jfield(result, "diagnostics") {
    Array(items) =>
      for d in items {
        let code = jstr(jfield(d, "code"))
        let line = jint(jfield(d, "line"))
        let col = jint(jfield(d, "column"))
        let msg = jstr(jfield(d, "message"))
        match jstr(jfield(d, "severity")) {
          "error" => {
            has_error = true
            if code == "E0" {
              println("// COMPILE-ERROR codegen \{msg}")
            } else {
              println("// COMPILE-ERROR \{code} \{line}:\{col} \{msg}")
            }
          }
          "warning" =>
            println("// COMPILE-WARNING \{code} \{line}:\{col} \{msg}")
          "hint" => println("// COMPILE-HINT \{code} \{line}:\{col} \{msg}")
          _ => ()
        }
      }
    _ => ()
  }
  // 帧 ok:false 但诊断零 error（结构性破损形态）按失败处理——fail loud
  if jfield(result, "ok") is False && !has_error {
    has_error = true
    println(
      "// COMPILE-ERROR codegen 编译失败但诊断通道为空（协议破损形态）",
    )
  }
  has_error
}

///|
/// 帧单源管线主体。json_mode=false 走文本渲染；true 走 NDJSON 事件流
///（原 json_event_stream 行为原样）。
fn frame_pipeline(
  src : String,
  file : String,
  stdin_file : String,
  argv : Array[String],
  dump_mem : String,
  clock_millis : () -> UInt64,
  write_stdout : (Bytes) -> Unit,
  json_mode : Bool,
  compile_mode? : Bool = false,
) -> Int {
  let mut id = 0
  let inv_raw = fn(method_name : String, params : String) -> String {
    id += 1
    @gateway.invoke(
      "{\"id\":\{id},\"method\":\"\{method_name}\",\"params\":\{params}}",
    )
  }
  let inv_tree = fn(method_name : String, params : String) -> Json? {
    id += 1
    @gateway.invoke_parsed(
      "{\"id\":\{id},\"method\":\"\{method_name}\",\"params\":\{params}}",
    )
  }
  @gateway.reset()
  // 墙钟注入（gateway 侧口——原文本模式 vm.set_clock_source 同源；json
  // 模式此前未注入系遗漏，随单源化统一补齐）
  @gateway.set_clock_source(clock_millis)
  ignore(inv_raw("session.create", "{}"))
  ignore(
    inv_raw(
      "config.set", "{\"max_steps\":10000000,\"call_depth_limit\":10000,\"deterministic\":true,\"quarantine_budget\":262144}",
    ),
  )
  // filename 装配（BUG-A 修复语义保留）：`-`（stdin 源）不传 filename；
  // 其余传全路径——gateway 侧 base_dir 语义（同目录 include）
  let compile_params = if file == "-" {
    "{\"source\":\"\{@util.json_escape(src)}\"}"
  } else {
    "{\"source\":\"\{@util.json_escape(src)}\",\"filename\":\"\{@util.json_escape(file)}\"}"
  }
  // ── compile 帧 ──
  if json_mode {
    let comp = inv_raw("compile", compile_params)
    println("{\"type\":\"diag\",\"frame\":\{comp}}")
    if comp.contains("\"ok\":false") {
      return 1
    }
  } else {
    let comp = inv_tree("compile", compile_params)
    match comp {
      Some(frame) => {
        let has_error = render_diag_frame(frame)
        if has_error {
          return 1
        }
      }
      None => {
        println(
          "// COMPILE-ERROR codegen compile 帧解析失败（协议破损形态）",
        )
        return 1
      }
    }
  }
  // ── compile 子命令出口（compile_mode：成功打 COMPILE-OK 返回 0——
  // 与原 cli_compile 文本形态逐字节同构）──
  if compile_mode {
    if json_mode {
      return 0
    }
    println("// COMPILE-OK")
    return 0
  }
  // ── run 段 ──
  // argv 恒下发（gateway 语义 = 完整 argv 含 argv[0]；零透传也发 [file]）
  let items = StringBuilder()
  items.write_string("\"\{@util.json_escape(file)}\"")
  for i = 0; i < argv.length(); i = i + 1 {
    items.write_string(",\"\{@util.json_escape(argv[i])}\"")
  }
  let argv_json = "\"argv\":[\{items.to_string()}]"
  // -i 批注入（与原两模式同构：run{input, batch_input:true}——批注入耗尽
  // 即 EOF；多行 scanf 循环不误 waiting）
  // #70 第二步：**恒发 batch_input:true**——无 -i 注入时 headless 语义
  //（scanf 耗尽即 EOF，旧文本模式 vm.set_input(from_stdin_text(_, true))
  // 同款；壳 main.js「无输入注入时 headless」同源。漏发则 gateway 会话
  // 默认 Interactive，空 stdin 的 scanf 变 waiting_input——cli_smoke 双臂
  // 对拍实锤）
  let input_json = if stdin_file != "" {
    let mut text = @fs.read_file_to_string(stdin_file) catch { _ => "" }
    if !text.has_suffix("\n") {
      text = text + "\n"
    }
    ",\"input\":\"\{@util.json_escape(text)}\",\"batch_input\":true"
  } else {
    ",\"batch_input\":true"
  }
  let run_req = "{\{argv_json}\{input_json}}"
  // ── 输出三帧拉取（stdout/stderr/note）──
  if json_mode {
    let run = inv_raw("run", run_req)
    println("{\"type\":\"run\",\"frame\":\{run}}")
    let out = inv_raw("output.delta", "{\"cursor\":0,\"stream\":\"stdout\"}")
    println("{\"type\":\"stdout\",\"frame\":\{out}}")
    let err = inv_raw("output.delta", "{\"cursor\":0,\"stream\":\"stderr\"}")
    println("{\"type\":\"stderr\",\"frame\":\{err}}")
    let note = inv_raw("output.delta", "{\"cursor\":0,\"stream\":\"note\"}")
    println("{\"type\":\"note\",\"frame\":\{note}}")
    if run.contains("\"status\":\"trap\"") {
      if run.contains("\"steps_executed\":10000000") {
        return 3
      }
      return 2
    }
    return 0
  }
  // 文本模式：结构化消费
  let run_frame = inv_tree("run", run_req)
  let run_result = match run_frame {
    Some(f) => jfield(f, "result")
    None => {
      println(
        "// COMPILE-ERROR codegen run 帧解析失败（协议破损形态）",
      )
      return 1
    }
  }
  fn delta_bytes(method_name : String, stream : String) -> Bytes {
    match inv_tree(method_name, "{\"cursor\":0,\"stream\":\"\{stream}\"}") {
      Some(f) => latin1_to_bytes(jstr(jfield(jfield(f, "result"), "delta")))
      None => b""
    }
  }
  // stdout：字节直写 + 尾换行保形（壳 writeStdoutBytes 同款）
  let raw = delta_bytes("output.delta", "stdout")
  let mut buf = raw
  if buf.length() == 0 || buf[buf.length() - 1] != b'\n' {
    buf = buf.add(b"\n")
  }
  write_stdout(buf)
  // stderr：还原字节 → UTF-8 优先解码 → `// STDERR` 标记行
  //（与拆除前 utf8_text_partial 同源形态）
  let etext = @util.utf8_text_partial(delta_bytes("output.delta", "stderr"))
  if !etext.is_empty() {
    for line in etext.split("\n") {
      if !line.is_empty() {
        println("// STDERR \{line}")
      }
    }
  }
  // note：完成附注 + 泄漏报告（gateway serve_run 合成——append_leak_report
  // 单源）。**Note 通道 delta 是 UTF-8 原文**（serve_io 分叉登记：Note 走
  // utf8_text_partial 解码回原文、非 Latin-1 折回——双重还原会 mojibake）
  let ntext = match
    inv_tree("output.delta", "{\"cursor\":0,\"stream\":\"note\"}") {
    Some(f) => jstr(jfield(jfield(f, "result"), "delta"))
    None => ""
  }
  if !ntext.is_empty() {
    for line in ntext.split("\n") {
      if !line.is_empty() {
        println("// NOTE \{line}")
      }
    }
  }
  // --dump-memory（文本模式独有——json 模式 spec §3 登记不适用）：帧通路
  // 的 memory.dump bytes_base64 解码落盘（原 vm.dump_memory_raw 等价）
  if dump_mem != "" {
    match inv_tree("memory.dump", "{}") {
      Some(f) =>
        match
          @util.base64_decode(jstr(jfield(jfield(f, "result"), "bytes_base64"))) {
          Some(bytes) =>
            @fs.write_bytes_to_file(dump_mem, bytes) catch {
              _ => ()
            }
          None => ()
        }
      None => ()
    }
  }
  // trap / EXIT 行 + 退出码（与拆除前 vm 事实同源——帧字段等价投影）
  if jstr(jfield(run_result, "status")) == "trap" {
    println("// TRAP \{jstr(jfield(run_result, "trap"))}")
    if jint(jfield(run_result, "steps_executed")) == 10000000 {
      return 3
    }
    return 2
  }
  let ret = jint(jfield(run_result, "return_value"))
  if ret != 0 {
    println("// EXIT \{ret}")
  }
  0
}
