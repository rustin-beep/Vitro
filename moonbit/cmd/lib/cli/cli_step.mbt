// cmd/lib/step：CLI `step` 主体（#37 批②——形态与序列约定见 moon.pkg）。
// JSON 请求拼装：源码走 JSON 字符串转义（escape_json——gateway 协议输入
// 是标准 JSON）；响应的 summary 提取用轻量字段判（gateway.json_parse 未
// 导出，本命令 summary 面只要 finished/trapped/payloads 计数——contains
// + 批计数足够，不做全解析）。

///|
pub fn step(args : Array[String], read_stdin : () -> Bytes) -> Int {
  let mut file = ""
  let mut json_mode = false
  // 默认 100_000 对齐 Rust unified（手册口径——2026-10-04 对照复核修正：
  // 初版硬编码 2_000_000 系实现自拍未登记形态差）
  let mut max_steps = 100000
  let mut i = 0
  while i < args.length() {
    if args[i] == "--json" {
      json_mode = true
    } else if args[i] == "--summary" {
      json_mode = false // 显式摘要模式（默认）
    } else if args[i] == "--max-steps" && i + 1 < args.length() {
      i += 1
      max_steps = parse_int_or(args[i], 100000)
    } else if (!args[i].has_prefix("-") || args[i] == "-") && file == "" {
      file = args[i]
    }
    i += 1
  }
  if file == "" {
    println("用法: step <file.c> [--max-steps N] [--json|--summary]")
    return 4
  }
  // `-` = 源码走 stdin（B2 全命令品类——同 compile 修正）
  let src = if file == "-" {
    utf8_decode(read_stdin())
  } else {
    @fs.read_file_to_string(file) catch {
      _ => ""
    }
  }
  guard src != "" else {
    println("// COMPILE-ERROR io 1:1 源文件不可读或为空：\{file}")
    return 4
  }
  // gateway.invoke 通道（协议单源；id 单调即可）
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
      "config.set",
      "{\"max_steps\":\{max_steps},\"call_depth_limit\":10000,\"deterministic\":true,\"quarantine_budget\":262144}",
    ),
  )
  let comp = inv("compile", "{\"source\":\"\{escape_json(src)}\"}")
  if comp.contains("\"ok\":false") {
    // 诊断在 compile 帧——文本模式透传 JSON 行（agent 可解析）；json 模式
    // 同样透传（type 语义由行内 ok:false 自明）
    println(comp)
    return 1
  }
  ignore(inv("run", "{}"))
  ignore(inv("step.begin", "{}"))
  let mut frames = 0
  let mut last : String = ""
  let mut finished = false
  let mut trapped = false
  let mut running = true
  while running {
    let r = inv("step.next", "{}")
    last = r
    frames += count_payloads(r)
    if json_mode {
      println(r)
    }
    if r.contains("\"finished\":true") {
      finished = true
      running = false
    } else if r.contains("\"trapped\":true") {
      trapped = true
      running = false
    } else if r.contains("\"waiting_input\":true") {
      running = false
    }
  }
  if json_mode {
    // 摘要末行（type:summary——NDJSON 事件流收口）
    println(
      "{\"type\":\"summary\",\"frames\":\{frames},\"finished\":\{finished},\"trapped\":\{trapped}}",
    )
  } else {
    println("帧数: \{frames}")
    println(
      "终态: \{if finished { "finished" } else if trapped { "trap" } else { "waiting_input/截断" }}",
    )
    if trapped {
      // trap 死因（轻提取：trap_message 字段串段——summary 模式够用）
      println("死因: \{extract_json_string_field(last, "trap_message")}")
    }
  }
  if trapped {
    return 2
  }
  0
}

///|
/// JSON 字符串转义（RFC 8259 面：源码文本 → JSON 字符串字面量内容）。
fn escape_json(s : String) -> String {
  let buf = StringBuilder()
  for c in s {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ =>
        if c.to_int() < 0x20 {
          buf.write_string("\\u")
          buf.write_string(to_hex4(c.to_int()))
        } else {
          buf.write_char(c)
        }
    }
  }
  buf.to_string()
}

///|
/// 轻量 JSON 字符串字段提取（"key":"value" 形态——summary 面专用，
/// 值内转义 \" 不还原（死因文案可读级））。
fn extract_json_string_field(json : String, key : String) -> String {
  let pat = "\"\{key}\":\""
  // 手扫首个匹配（core String.find 参数形态不同——避免 API 面依赖）
  let mut start = -1
  let mut k = 0
  while k <= json.length() - pat.length() {
    if json.substring(start=k, end=k + pat.length()) == pat {
      start = k
      break
    }
    k += 1
  }
  if start < 0 {
    ""
  } else {
    let from = start + pat.length()
    let cs = json.to_array()
    let buf = StringBuilder()
    let mut j = from
    while j < cs.length() {
      if cs[j] == '"' {
        break
      }
      if cs[j] == '\\' && j + 1 < cs.length() && cs[j + 1] == '"' {
        buf.write_char('"')
        j += 2
        continue
      }
      if cs[j] == '\\' && j + 1 < cs.length() && cs[j + 1] == 'n' {
        buf.write_char('\n')
        j += 2
        continue
      }
      buf.write_char(cs[j])
      j += 1
    }
    buf.to_string()
  }
}

///|
/// 批内帧计数（"payloads":[ 计数组元素——轻提取：数 `[` 后顶层对象数近似：
/// 数 `"step_index":` 出现次数——每帧恰好一个）。
fn count_payloads(batch_json : String) -> Int {
  let mut n = 0
  let pat = "\"step_index\":"
  let cs = batch_json.to_array()
  let mut i = 0
  while i <= cs.length() - pat.length() {
    if batch_json.substring(start=i, end=i + pat.length()) == pat {
      n += 1
      i += pat.length()
    } else {
      i += 1
    }
  }
  n
}

///|
fn parse_int_or(s : String, default : Int) -> Int {
  let mut v = 0
  let mut ok = false
  for c in s {
    if c >= '0' && c <= '9' {
      v = v * 10 + (c.to_int() - '0'.to_int())
      ok = true
    } else {
      return default
    }
  }
  if ok {
    v
  } else {
    default
  }
}

///|
/// 四位十六进制（\u 转义专用——控制字符面）。
fn to_hex4(v : Int) -> String {
  let digits = "0123456789abcdef"
  let mut out = ""
  out += digits[v / 4096 % 16].to_string()
  out += digits[v / 256 % 16].to_string()
  out += digits[v / 16 % 16].to_string()
  out += digits[v % 16].to_string()
  out
}
