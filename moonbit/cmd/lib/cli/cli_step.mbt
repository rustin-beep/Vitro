// cmd/lib/step：CLI `step` 主体（#37 批②——形态与序列约定见 moon.pkg）。
// JSON 请求拼装：源码走 JSON 字符串转义（@util.json_escape——gateway
// 协议输入是标准 JSON）；响应消费 SWEEP1 批（#443 B2，2026-11-05）起统一
// 结构化路径（invoke_parsed + jfield——与 cli_frame 单源同风格）：文本模式
// output.delta 的字节还原 = json_parse 转义还原 + latin1_to_bytes 折回
//（72 行手扫 decode_delta_stdout 已删，D1 负索引 panic 面随之消灭）；
// summary 面的帧计数/终态标记仍用轻量 contains（计数语义足够，不引入
// 全解析开销）。

///|
pub fn step(
  args : Array[String],
  read_stdin : () -> Bytes,
  write_stdout : (Bytes) -> Unit,
  channel~ : EngineChannel,
) -> Int32 {
  ensure_include_reader(channel)
  let mut file = ""
  let mut json_mode = false
  // --wasm-rehost（REHOST 批 3）：step 态装载走 wasm 载体往返——与 run
  // 态 `--wasm-rehost`（批 2b）**独立并行**的旗标（设计单 §3.2 批 3 回退
  // 点：step 态 flag 可单独关）。flag 只随 step.begin 帧下发（预跑 run 帧
  // 不带——run 通道旗标独立；预跑副作用仅 runtime_argv 落定，其执行态
  // 被 step.begin 的 output.clear + setup 重建整体覆盖，装载形态不影响
  // step 帧流）；缺省 false 行为零扰动
  let mut wasm_rehost = false
  // 默认 100_000（2026-10-04 对照复核拍板值，历史蓝本 unified 同值〔tag
  // rust-oracle-freeze〕；初版硬编码 2_000_000 系实现自拍未登记形态差）
  let mut max_steps = 100000
  let mut i = 0
  while i < args.length() {
    if args[i] == "--json" {
      json_mode = true
    } else if args[i] == "--wasm-rehost" {
      wasm_rehost = true
    } else if args[i] == "--summary" {
      json_mode = false // 显式摘要模式（默认）
    } else if args[i] == "--max-steps" {
      // B3 批（2026-11-02，M35 A3）：尾置缺值先于「未知旗标」臂判——旧条件
      // 把 `i + 1 < length` 揉进同一分支，尾置时落到未知旗标臂报「未知旗标：
      // --max-steps」（已知旗标误报未知，run 同参数报「尾置缺值」——两子命令
      // 文案分叉）。rc=4 不变，文案对齐 run。
      if i + 1 >= args.length() {
        say("用法错: --max-steps 尾置缺值（须跟正整数）")
        say(
          "用法: step <file.c> [--max-steps N] [--wasm-rehost] [--json|--summary]",
        )
        return 4
      }
      i += 1
      // 非数字 = 用法错（2026-10-04 二轮审 P3：静默回落 100000 违反
      // 「禁止静默 default」纪律——对齐 Rust unified 的 eprintln+exit）
      match parse_int(args[i]) {
        Some(v) =>
          // B3 批（M35 A2）：下界域检对齐 run——旧形态无下界，`--max-steps 0`
          // 下发 config.set 后被 gateway #94 低下界钳成 1、钳制回包被 ignore 吞，
          // 静默按 1 步跑（run 同参数 rc=4 拒绝——同参数两子命令行为分叉）。
          // 上界由 parse_int 的 Int32 溢出预检承担（#133：超 2147483647 直接
          // None 走「需要整数」臂）——此处只判下界，不写不可达的 `v > 2147483647`
          //（PR #450 审阅 P3-1：旧写法把「1..=2147483647」说成域检面，实为夸大）。
          if v < 1 {
            say(
              "用法错: --max-steps 须 ≥ 1，得到 '\{args[i]}'（上限 2147483647 由整数域钳制；更大负载用 serve/api 的 config.set preset:algo）",
            )
            return 4
          } else {
            max_steps = v
          }
        None => {
          say("用法错: --max-steps 需要整数，得到 '\{args[i]}'")
          return 4
        }
      }
    } else if (!args[i].has_prefix("-") || args[i] == "-") && file == "" {
      file = args[i]
    } else if args[i].has_prefix("-") && args[i] != "-" {
      // 病 87 残留⑦（2026-10-13，方案 A）：未知旗标 fail loud——
      // run 已严格（DX P1）step 漏，旧 --xyz 被静默吞照常出帧
      say("vitro step: 未知旗标：\{args[i]}")
      say(
        "用法: step <file.c> [--max-steps N] [--wasm-rehost] [--json|--summary]",
      )
      return 4
    } else if file != "" {
      say(
        "vitro step: 多余位置参数 '\{args[i]}'（step 是单文件命令）",
      )
      say(
        "用法: step <file.c> [--max-steps N] [--wasm-rehost] [--json|--summary]",
      )
      return 4
    }
    i += 1
  }
  if file == "" {
    say(
      "用法: step <file.c> [--max-steps N] [--wasm-rehost] [--json|--summary]",
    )
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
    say("// COMPILE-ERROR io 1:1 源文件不可读或为空：\{file}")
    return 4
  }
  // gateway.invoke 通道（协议单源；id 单调即可）——raw 与结构化两形态
  //（SWEEP1 #443 B2：结构化消费与 cli_frame 单源同风格）
  let mut id = 0
  let inv = fn(method_name : String, params : String) -> String {
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
  ignore(inv("session.create", "{}"))
  ignore(
    inv(
      "config.set",
      "{\"max_steps\":\{max_steps},\"call_depth_limit\":10000,\"deterministic\":true,\"quarantine_budget\":262144}",
    ),
  )
  // compile params 装配走通道（直连 = source+filename；wasm = files 多文件）
  let compile_params = (channel.compile_params)(file, src)
  let comp = inv("compile", compile_params)
  if comp.contains("\"ok\":false") {
    // 诊断在 compile 帧——json 模式 type:diag 包装出 stdout（#444 协议面
    // 收口，2026-11-12：旧裸帧直出是三子命令中唯一不包装的，事件流消费方
    // 按 type 分派须对 step 失败行特判；现与 frame_pipeline 的 run/compile
    // --json 同形）；文本模式走 stderr（#129 通道分立：stdout 只承载
    // 程序输出）
    if json_mode {
      out_line(write_stdout, "{\"type\":\"diag\",\"frame\":\{comp}}")
    } else {
      say(comp)
    }
    return 1
  }
  // run 帧带 argv [file]（2026-10-04 二轮审 P1-A 同根：step 无 argv 面但
  // argv[0] 语义必须有——gateway 默认 [] 会让 argv[0] 解引用 NULL trap）。
  // SWEEP1 #443 D2：外层 ok:false（协议错帧 {id,ok:false,error} 无 result）
  // 早退 fail loud——修前 ignore 吞帧照常推进。判定走结构化外层位：内层
  // result.ok:false 是 trap 帧的合法中间态（run_outcome_json L67），contains
  // 形态会误判
  let run_resp = inv("run", "{\"argv\":[\"\{@util.json_escape(file)}\"]}")
  let run_tree : Json? = json_parse_opt(run_resp)
  let run_ok = match run_tree {
    Some(f) => !(jfield(f, "ok") is False)
    None => false // 解析失败 = 协议破损形态
  }
  if !run_ok {
    if json_mode {
      out_line(write_stdout, "{\"type\":\"diag\",\"frame\":\{run_resp}}")
    } else {
      say("vitro step: run 帧协议错（详见帧文本）：\{run_resp}")
    }
    return 1
  }
  // REHOST 批 3：装载 flag 随 step.begin 帧下发（帧参数域——与 run 帧的
  // 批 2b 形态同款）；返回帧携带 wasm_rehost 状态串（flag on 才非空）——
  // stderr 标记行 `// WASM-REHOST-STEP <status>` 消费（与 run 通道的
  // `// WASM-REHOST` 区分通道；不进 stdout/digest 消费面）。装载回退
  // （fallback 形态）不打断 step 流——fail loud 归 flag on 形态的防线
  // （STEP-INV --rehost 轮断言 ok 形态，与批 2b rundiff「fallback 即红」
  // 同款纪律）
  let rehost_param = if wasm_rehost { "{\"wasm_rehost\":true}" } else { "{}" }
  let begin_resp = inv("step.begin", rehost_param)
  if wasm_rehost {
    let begin_tree = json_parse_opt(begin_resp)
    let st = match begin_tree {
      Some(f) => jstr(jfield(jfield(f, "result"), "wasm_rehost"))
      None => ""
    }
    if !st.is_empty() {
      say("// WASM-REHOST-STEP \{st}")
    }
  }
  let mut frames = 0
  let mut last : String = ""
  let mut finished = false
  let mut trapped = false
  let mut running = true
  // SWEEP1 #443 D2：批次上限兜底——每批 step.next 至少推进 1 步（gateway
  // 步数预算墙 = config.set max_steps），批数 > max_steps + 余量即帧流
  // 无三态终止的协议破损形态，fail loud 早退（修前 while running 理论
  // 死循环——错误帧无 finished/trapped/waiting_input 三标记时永真）
  let batch_cap = max_steps + 16
  let mut batches = 0
  while running {
    let r = inv("step.next", "{}")
    last = r
    frames += count_payloads(r)
    if json_mode {
      out_line(write_stdout, r)
    }
    if r.contains("\"finished\":true") {
      finished = true
      running = false
    } else if r.contains("\"trapped\":true") {
      trapped = true
      running = false
    } else if r.contains("\"waiting_input\":true") {
      running = false
    } else {
      // 帧级失败即时传导（对齐 api 两层判据先例——协议 §4.5；step 协议
      // 面 §5 同款登记）：无三态标记的 step.next 帧 ok:false（协议级错
      // 帧，result 缺省）——旧形态落 batch_cap 兜底空转（cap 次调用后以
      // 「协议破损」文案 rc=1——归因变形；默认 max_steps=100000 即十万
      // 次空转）。判定走结构化外层 ok 位（PR #509 审阅 P3-2：与上方 run
      // 臂同源——contains 子串绑死紧凑序列化形态，协议面一旦换带空格的
      // stringify 即静默退化回十万次空转；step.next 的 result 是
      // AutoStepResult 投影无 ok 键，外层位唯一语义）。解析失败（None）
      // = 协议破损形态，与 run 臂同款视同帧级失败 fail loud。
      let next_ok = match json_parse_opt(r) {
        Some(f) => !(jfield(f, "ok") is False)
        None => false
      }
      if !next_ok {
        say("vitro step: step.next 帧级失败（ok:false）——\{r}")
        return 1
      }
    }
    batches += 1
    if running && batches >= batch_cap {
      say(
        "vitro step: step.next 批次超上限（\{batch_cap}）——帧流无三态终止（协议破损形态）",
      )
      return 1
    }
  }
  if json_mode {
    // 程序 stdout 帧（#57-1：step 流不含 stdout——预跑 run 的输出被
    // step.begin 的 output.clear() 清掉，重跑产物只在 vm 输出通道；本行
    // 与 run --json 的 type:stdout 帧同形，summary 收口行之前）
    let out = inv("output.delta", "{\"cursor\":0,\"stream\":\"stdout\"}")
    out_line(write_stdout, "{\"type\":\"stdout\",\"frame\":\{out}}")
    // 摘要末行（type:summary——NDJSON 事件流收口）
    out_line(
      write_stdout,
      "{\"type\":\"summary\",\"frames\":\{frames},\"finished\":\{finished},\"trapped\":\{trapped}}",
    )
  } else {
    say("帧数: \{frames}")
    say(
      "终态: \{if finished { "finished" } else if trapped { "trap" } else { "waiting_input/截断" }}",
    )
    if trapped {
      // trap 死因（轻提取：trap_message 字段串段——summary 模式够用）
      say("死因: \{extract_json_string_field(last, "trap_message")}")
    }
    // 程序 stdout 原样直写（#57-1：终态行后——文本模式消费面 = shell 管道
    // 拿原文，与 run 文本模式同契约；delta 为 Latin-1 折回文本，反折回字
    // 节域经 write_stdout 直写，putchar(200) 单字节保真同款）。SWEEP1
    // #443 B2/D1：消费改结构化路径（invoke_parsed + jfield("delta") +
    // latin1_to_bytes——与 cli_frame.delta_bytes 单源同风格）；72 行手扫
    // decode_delta_stdout（RFC 8259 逐字符解码 + \uXXXX 防御臂）已删，
    // 转义还原语义由 json_parse 单源承担（等价锚 sweep1_443_b2），缺
    // delta 字段的负索引 panic 面随之消灭（sweep1_443_d1）
    let bytes = match
      inv_tree("output.delta", "{\"cursor\":0,\"stream\":\"stdout\"}") {
      Some(f) => latin1_to_bytes(jstr(jfield(jfield(f, "result"), "delta")))
      None => b""
    }
    if bytes.length() > 0 {
      write_stdout(bytes)
    }
  }
  if trapped {
    // 退出码分档（契约 §2：3=步数超限 / 2=trap——与 run 同口径）。step 帧
    // 无结构化步数位（max_collected_step 超限时 None——2026-10-04 探针实测），
    // 判 trap_message 的**引擎固定文案前缀**「程序执行步数达到预算上限」（比泛
    // 「步数」收窄到零误命中面；该文案是引擎模板字符串——单源
    // teaching/assets/trap_messages_gen.mbt 的 step-limit 模板，变更连坐此处
    // 与 cli_wbtest m35_a2 锚；spec §2 限定句在案）。
    // B3 批（2026-11-02，M35 A2'）：旧判定串「程序执行步数超过限制」是引擎
    // 文案翻新前的形态，模板改为「达到预算上限」后此处未连坐——子串永不命
    // 中，所有 step-limit 恒落 rc=2（契约 3 在 step 子命令上从不成立，教学
    // 预算墙的 shell 判 `$? == 3` 全部失灵）。
    if extract_json_string_field(last, "trap_message").contains(
        "程序执行步数达到预算上限",
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
fn count_payloads(batch_json : String) -> Int32 {
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
fn parse_int(s : String) -> Int32? {
  if s.length() == 0 {
    return None
  }
  let mut v = 0
  for c in s {
    if c >= '0' && c <= '9' {
      // #133 止血包（2026-10-16）：溢出防护——Int32 静默回绕使
      // `--max-steps 9999999999` 回绕值恰好落合法域被静默接受
      //（step/run 两消费面同病）。进位前预检（v*10+d 超 Int32 顶即 None）
      let d = c.to_int() - '0'.to_int()
      if v > 214748364 || (v == 214748364 && d > 7) {
        return None
      }
      v = v * 10 + d
    } else {
      return None
    }
  }
  Some(v)
}

// to_hex4 已随 escape_json 本地副本一并退役（转义单源 @util.json_escape，
// issue #55 六份收一）。decode_delta_stdout + parse_hex4 亦随 SWEEP1 批
//（#443 B2，2026-11-05）退役——output.delta 消费改 invoke_parsed + jfield
// 结构化路径（json_parse 转义还原 + latin1_to_bytes 折回，与 cli_frame
// delta_bytes 单源同风格）。
