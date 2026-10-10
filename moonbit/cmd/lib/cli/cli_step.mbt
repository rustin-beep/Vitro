// cmd/lib/step：CLI `step` 主体（#37 批②——形态与序列约定见 moon.pkg）。
// JSON 请求拼装：源码走 JSON 字符串转义（@util.json_escape——gateway
// 协议输入是标准 JSON）；响应的 summary 提取用轻量字段判（gateway.json_parse 未
// 导出，本命令 summary 面只要 finished/trapped/payloads 计数——contains
// + 批计数足够，不做全解析）。

///|
pub fn step(
  args : Array[String],
  read_stdin : () -> Bytes,
  write_stdout : (Bytes) -> Unit,
) -> Int {
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
      // 非数字 = 用法错（2026-10-04 二轮审 P3：静默回落 100000 违反
      // 「禁止静默 default」纪律——对齐 Rust unified 的 eprintln+exit）
      match parse_int(args[i]) {
        Some(v) => max_steps = v
        None => {
          println("用法错: --max-steps 需要整数，得到 '\{args[i]}'")
          return 4
        }
      }
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
    @util.utf8_text_partial(read_stdin())
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
      "config.set",
      "{\"max_steps\":\{max_steps},\"call_depth_limit\":10000,\"deterministic\":true,\"quarantine_budget\":262144}",
    ),
  )
  // filename 装配（BUG-A 修复，2026-10-05）：同 cli_compile——丢 filename
  // 则 base_dir 退化、同目录 include 断；stdin（"-"）不传
  let compile_params = if file == "-" {
    "{\"source\":\"\{@util.json_escape(src)}\"}"
  } else {
    "{\"source\":\"\{@util.json_escape(src)}\",\"filename\":\"\{@util.json_escape(file)}\"}"
  }
  let comp = inv("compile", compile_params)
  if comp.contains("\"ok\":false") {
    // 诊断在 compile 帧——文本模式透传 JSON 行（agent 可解析）；json 模式
    // 同样透传（type 语义由行内 ok:false 自明）
    println(comp)
    return 1
  }
  // run 帧带 argv [file]（2026-10-04 二轮审 P1-A 同根：step 无 argv 面但
  // argv[0] 语义必须有——gateway 默认 [] 会让 argv[0] 解引用 NULL trap）
  ignore(inv("run", "{\"argv\":[\"\{@util.json_escape(file)}\"]}"))
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
    // 程序 stdout 帧（#57-1：step 流不含 stdout——预跑 run 的输出被
    // step.begin 的 output.clear() 清掉，重跑产物只在 vm 输出通道；本行
    // 与 run --json 的 type:stdout 帧同形，summary 收口行之前）
    let out = inv("output.delta", "{\"cursor\":0,\"stream\":\"stdout\"}")
    println("{\"type\":\"stdout\",\"frame\":\{out}}")
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
    // 程序 stdout 原样直写（#57-1：终态行后——文本模式消费面 = shell 管道
    // 拿原文，与 run 文本模式同契约；delta 为 Latin-1 折回文本，反折回字
    // 节域经 write_stdout 直写，putchar(200) 单字节保真同款）
    let out = inv("output.delta", "{\"cursor\":0,\"stream\":\"stdout\"}")
    let bytes = decode_delta_stdout(out)
    if bytes.length() > 0 {
      write_stdout(bytes)
    }
  }
  if trapped {
    // 退出码分档（契约 §2：3=步数超限 / 2=trap——与 run 同口径）。step 帧
    // 无结构化步数位（max_collected_step 超限时 None——2026-10-04 探针实测），
    // 判 trap_message 的**引擎固定文案前缀**「程序执行步数超过限制」（比泛
    // 「步数」收窄到零误命中面；该文案是引擎格式字符串，变更连坐此处——
    // spec §2 限定句在案）
    if extract_json_string_field(last, "trap_message").contains(
        "程序执行步数超过限制",
      ) {
      return 3
    }
    return 2
  }
  0
}

// 字符串转义已收口 @util.json_escape（issue #55 六份收一；原本地
// escape_json 语义一致——RFC 8259 全量控制字符 \u00XX，hex 同小写）。

///|
/// 轻量 JSON 字符串字段提取（"key":"value" 形态——summary 面专用，
/// 值内转义 \" 不还原（死因文案可读级））。
fn extract_json_string_field(json : String, key : String) -> String {
  let pat = "\"\{key}\":\""
  // 手扫首个匹配（core String.find 参数形态不同——避免 API 面依赖）
  let mut start = -1
  let mut k = 0
  while k <= json.length() - pat.length() {
    if json[k:k + pat.length()].to_owned() == pat {
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
    if batch_json[i:i + pat.length()].to_owned() == pat {
      n += 1
      i += pat.length()
    } else {
      i += 1
    }
  }
  n
}

///|
/// 整数解析（非数字/空 → None——调用方判用法错；2026-10-04 二轮审 P3
/// 弃 parse_int_or 静默 default 形态）
fn parse_int(s : String) -> Int? {
  if s.length() == 0 {
    return None
  }
  let mut v = 0
  for c in s {
    if c >= '0' && c <= '9' {
      v = v * 10 + (c.to_int() - '0'.to_int())
    } else {
      return None
    }
  }
  Some(v)
}

// to_hex4 已随 escape_json 本地副本一并退役（转义单源 @util.json_escape，
// issue #55 六份收一）。

///|
/// output.delta 帧的 stdout 文本反折回字节域（#57-1 文本模式专用，
/// 单步完整解码——不经 extract_json_string_field：其 \" / \n 部分还原
/// 对含字面反斜杠的 stdout 有损，程序输出 `\n` 两字节〔JSON 文本 `\\n`〕
/// 会被误还原为换行）：帧内定位 `"delta":"` 值段，按 RFC 8259 转义还原
/// （\" \\ \/ \b \f \n \r \t \uXXXX；json_escape 只对 <0x20 与引号反斜杠
/// 转义，\u 域 ≤0x1F 取低字节）+ 非 ASCII char 取低 8 位（delta 是
/// Latin-1 逐字节折回文本——gateway serve_io 通道分域，C 程序字节流口
/// 径），产出与程序原 stdout 逐字节一致。
fn decode_delta_stdout(frame : String) -> Bytes {
  let pat = "\"delta\":\""
  let cs = frame.to_array()
  let mut start = -1
  let mut k = 0
  while k <= cs.length() - pat.length() {
    if frame[k:k + pat.length()].to_owned() == pat {
      start = k + pat.length()
      break
    }
    k += 1
  }
  let buf : Array[Byte] = []
  let mut i = start
  while i < cs.length() {
    let c = cs[i]
    if c == '"' {
      break
    }
    if c == '\\' && i + 1 < cs.length() {
      let n = cs[i + 1]
      let b : Int = match n {
        '"' => 0x22
        '\\' => 0x5C
        '/' => 0x2F
        'b' => 0x08
        'f' => 0x0C
        'n' => 0x0A
        'r' => 0x0D
        't' => 0x09
        'u' => {
          // \uXXXX：json_escape 域 ≤0x1F（低字节即原字节）；防御性兼容
          // 高码点——按 UTF-8 编码写入（不可达域，emitter 不产）
          if i + 5 < cs.length() {
            let cp = parse_hex4(cs[i + 2], cs[i + 3], cs[i + 4], cs[i + 5])
            if cp <= 0xFF {
              buf.push(cp.to_byte())
              i += 6
              continue
            }
            if cp < 0x80 {
              buf.push(cp.to_byte())
            } else if cp < 0x800 {
              buf.push((0xC0 | (cp >> 6)).to_byte())
              buf.push((0x80 | (cp & 0x3F)).to_byte())
            } else if cp < 0x10000 {
              buf.push((0xE0 | (cp >> 12)).to_byte())
              buf.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
              buf.push((0x80 | (cp & 0x3F)).to_byte())
            } else {
              buf.push((0xF0 | (cp >> 18)).to_byte())
              buf.push((0x80 | ((cp >> 12) & 0x3F)).to_byte())
              buf.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
              buf.push((0x80 | (cp & 0x3F)).to_byte())
            }
            i += 6
            continue
          }
          0x5C
        }
        _ => 0x5C
      }
      buf.push(b.to_byte())
      i += 2
    } else {
      // Latin-1 反折：每 char 低 8 位（≥0x80 字节折回域）
      buf.push((c.to_int() & 0xFF).to_byte())
      i += 1
    }
  }
  Bytes::from_array(buf)
}

///|
/// 四位十六进制解析（decode_delta_stdout 的 \uXXXX 臂；非法位 = 0——
/// gateway emitter 只产合法序列，防御性兜底）。
fn parse_hex4(a : Char, b : Char, c : Char, d : Char) -> Int {
  let h = fn(ch : Char) -> Int {
    let v = ch.to_int()
    if v >= '0'.to_int() && v <= '9'.to_int() {
      v - '0'.to_int()
    } else if v >= 'a'.to_int() && v <= 'f'.to_int() {
      v - 'a'.to_int() + 10
    } else if v >= 'A'.to_int() && v <= 'F'.to_int() {
      v - 'A'.to_int() + 10
    } else {
      0
    }
  }
  (h(a) << 12) | ((h(b) << 8) | ((h(c) << 4) | h(d)))
}
