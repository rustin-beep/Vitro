// #70 第二步（2026-10-11）：gateway 帧单源管线——run/compile 两子命令的
// json 模式（NDJSON 事件流）与文本模式（帧→标记行渲染）共用同一 invoke
// 序列。旧 compile_and_report 直调管线（lexer→parser→typeck→codegen 手拼
// + println）拆除：诊断出口从此单源（#64「双臂不对账」的病根——同一
// codegen 失败 exe 打印 / gateway 吞诊断——两出口自此同帧同渲染）。
//
// 文本模式契约（拆除期「逐字节对齐旧壳形态」锚已随 #207/#319 契约翻新——
// 尾换行不再对齐旧形态）：`// COMPILE-ERROR|WARNING|HINT <code|codegen>
// <l>:<c> <msg>` + `// COMPILE-OK`；run 段 `// STDERR/NOTE/TRAP/EXIT` 行 +
// stdout 字节直写（Latin-1 折回还原，原样零修饰——与 clang / `--json`
// delta / step 文本模式四口径一致，spec §1「字节精确·无需剥离」）。
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
fn jint(v : Json) -> Int32 {
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
/// #394 审阅 P2-1（2026-10-31）：stdout 直写后、首条 stderr 标记行前的
/// 边界换行决策——stdout 非空且末字节非 `\n` 时返回 1 字节 `\n`（写入
/// **stderr**，stdout 字节不动）。`2>&1` 合流人读形态防粘连：修前 js 臂
/// `abc// NOTE …` 粘连成行（fs.writeSync(1) 先落、say 后落）、native 臂
/// CRT 缓冲序反转 `// NOTE …\nabc`——三臂合流形态互不一致；空 stdout
/// 不补（无行可粘）、自带尾换行不补（行已对齐）。三臂同补字节同形
///（js/wasm = fs.writeSync(2)、native = CRT 二进制模式 fwrite——#315
/// 治本后 `\n` 不翻 CRLF）。
fn stderr_boundary_newline(raw : Bytes) -> Bytes {
  if raw.length() > 0 && raw[raw.length() - 1].to_int() != 0x0A {
    b"\n"
  } else {
    b""
  }
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
              say("// COMPILE-ERROR codegen \{msg}")
            } else {
              say("// COMPILE-ERROR \{code} \{line}:\{col} \{msg}")
            }
            // DX ②：同 warning 臂——error 级修复建议带出
            let fix = jstr(jfield(d, "fix_suggestion"))
            if fix != "" {
              say("// FIX \{fix}")
            }
          }
          "warning" => {
            say("// COMPILE-WARNING \{code} \{line}:\{col} \{msg}")
            // DX ②（#71 工具批，2026-10-11）：fix_suggestion 文本模式带出
            //（新前缀 FIX——协议「前缀只增不改」追加面；此前仅 --json 帧
            // 可见，学生最常用面只能看不能修）
            let fix = jstr(jfield(d, "fix_suggestion"))
            if fix != "" {
              say("// FIX \{fix}")
            }
          }
          "hint" => say("// COMPILE-HINT \{code} \{line}:\{col} \{msg}")
          _ => ()
        }
      }
    _ => ()
  }
  // 帧 ok:false 但诊断零 error（结构性破损形态）按失败处理——fail loud
  if jfield(result, "ok") is False && !has_error {
    has_error = true
    say(
      "// COMPILE-ERROR codegen 编译失败但诊断通道为空（协议破损形态）",
    )
  }
  has_error
}

///|
/// 帧单源管线主体。json_mode=false 走文本渲染；true 走 NDJSON 事件流
///（原 json_event_stream 行为原样）。channel 默认直连（native/js）；
/// wasm 壳注入 wasm 产物 invoke 通道（main.js 退役批）。
fn frame_pipeline(
  src : String,
  file : String,
  stdin_file : String,
  argv : Array[String],
  dump_mem : String,
  clock_millis : () -> UInt64,
  write_stdout : (Bytes) -> Unit,
  json_mode : Bool,
  compile_mode~ : Bool = false,
  channel~ : EngineChannel,
  max_steps_override~ : Int32? = None,
  realtime~ : Bool = false,
) -> Int32 {
  // #133 止血包：--max-steps 覆盖值（缺省 10M）——config.set 下发与
  // rc=3 步数超限判定（两处）同源此值
  let ms_cap = max_steps_override.unwrap_or(10000000)
  let mut id = 0
  let inv_raw = fn(method_name : String, params : String) -> String {
    id += 1
    (channel.invoke)(
      "{\"id\":\{id},\"method\":\"\{method_name}\",\"params\":\{params}}",
    )
  }
  let inv_tree = fn(method_name : String, params : String) -> Json? {
    id += 1
    (channel.invoke_parsed)(
      "{\"id\":\{id},\"method\":\"\{method_name}\",\"params\":\{params}}",
    )
  }
  (channel.reset)()
  // 墙钟注入（gateway 侧口——原文本模式 vm.set_clock_source 同源；json
  // 模式此前未注入系遗漏，随单源化统一补齐；wasm 臂 no-op 恒 0——分臂
  // 登记形态）
  (channel.set_clock)(clock_millis)
  ignore(inv_raw("session.create", "{}"))
  // #211（2026-10-22）：deterministic 默认 true（判分可复现——time/clock
  // 恒 0、digest 冻结依赖）；--realtime 置 false 走宿主墙钟（教学面：
  // srand(time(0)) / clock() 计时）
  let det_flag = !realtime
  ignore(
    inv_raw(
      "config.set",
      "{\"max_steps\":\{ms_cap},\"call_depth_limit\":10000,\"deterministic\":\{det_flag},\"quarantine_budget\":262144}",
    ),
  )
  // compile params 装配走通道（直连 = source+filename；wasm = files 多
  // 文件——quote-include 的 wasm 语义）
  let compile_params = (channel.compile_params)(file, src)
  // ── compile 帧 ──
  if json_mode {
    let comp = inv_raw("compile", compile_params)
    out_line(write_stdout, "{\"type\":\"diag\",\"frame\":\{comp}}")
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
        say(
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
    say("// COMPILE-OK")
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
    // DX P3（#71 顺手批，2026-10-11）：读失败 fail loud（rc=4）——此前
    // catch 静默空串，typo 文件名程序按 EOF「看似正常」跑完（病 83）
    let mut text = @fs.read_file_to_string(stdin_file) catch {
      _ => {
        say("vitro run: -i 输入文件不可读：\{stdin_file}")
        return 4
      }
    }
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
    out_line(write_stdout, "{\"type\":\"run\",\"frame\":\{run}}")
    let out = inv_raw("output.delta", "{\"cursor\":0,\"stream\":\"stdout\"}")
    out_line(write_stdout, "{\"type\":\"stdout\",\"frame\":\{out}}")
    let err = inv_raw("output.delta", "{\"cursor\":0,\"stream\":\"stderr\"}")
    out_line(write_stdout, "{\"type\":\"stderr\",\"frame\":\{err}}")
    let note = inv_raw("output.delta", "{\"cursor\":0,\"stream\":\"note\"}")
    out_line(write_stdout, "{\"type\":\"note\",\"frame\":\{note}}")
    if run.contains("\"status\":\"trap\"") {
      if run.contains("\"steps_executed\":\{ms_cap}") {
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
      say(
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
  // stdout：字节直写，原样零修饰（#207/#319，2026-10-31——文本模式
  // stdout 只承载程序输出，不补尾换行：末行无换行保持原样、空输出
  // 0 字节。与 clang / `--json` delta / step 文本模式四口径一致；
  // cli_step.mbt 直写同款）
  let raw = delta_bytes("output.delta", "stdout")
  if raw.length() > 0 {
    write_stdout(raw)
    // P2-1（#394 审阅处置）：stdout 末字节非 \n 时首条 stderr 标记行前补
    // 边界换行到 stderr——stdout 字节不动（spec §1 字节精确承诺不破）
    let bnd = stderr_boundary_newline(raw)
    if bnd.length() > 0 {
      cli_stderr_write(bnd)
    }
  }
  // stderr：还原字节 → UTF-8 优先解码 → `// STDERR` 标记行
  //（与拆除前 utf8_text_partial 同源形态）
  let etext = @util.utf8_text_partial(delta_bytes("output.delta", "stderr"))
  if !etext.is_empty() {
    for line in etext.split("\n") {
      if !line.is_empty() {
        say("// STDERR \{line}")
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
        say("// NOTE \{line}")
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
            // DX P4（#71 顺手批，2026-10-11）：写失败 fail loud（rc=4）——
            // 此前静默吞，用户以为落盘成功（病 83 双发面）
            @fs.write_bytes_to_file(dump_mem, bytes) catch {
              _ => {
                say("vitro run: --dump-memory 写盘失败：\{dump_mem}")
                return 4
              }
            }
          None => ()
        }
      None => ()
    }
  }
  // trap / EXIT 行 + 退出码（与拆除前 vm 事实同源——帧字段等价投影）
  if jstr(jfield(run_result, "status")) == "trap" {
    say("// TRAP \{jstr(jfield(run_result, "trap"))}")
    if jint(jfield(run_result, "steps_executed")) == ms_cap {
      return 3
    }
    return 2
  }
  let ret = jint(jfield(run_result, "return_value"))
  if ret != 0 {
    say("// EXIT \{ret}")
  }
  0
}
