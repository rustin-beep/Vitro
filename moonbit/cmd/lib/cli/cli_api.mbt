// cmd/lib/cli：`api` 子命令（2026-10-04 用户拍板补——「剩余 CLI 不给就得
// 前端人肉测、serve 交互式 stdio 难脚本统一测试」）。两形态：
//
//   单帧：`vitro api <method> '<json-params>'` → 一次 invoke → 帧直出 → 退出
//   批式：`vitro api --batch` ← stdin 喂 NDJSON 请求帧序列 → 同进程顺序
//         invoke → 响应 NDJSON → EOF 退出——**状态跨帧保留**（同 gateway
//         会话），step.begin→next→seek/payload.get/breakpoints/input.feed
//         续跑等前置依赖序列自此全部可脚本化（与 serve 的区别：管道终止型
//         ——脚本无逐行交互锁需求，cat frames | vitro api --batch 即全链）。
//
// 全部协议方法（含 dump 族/memory/output.delta/session 族；方法数单源
// = api_help_gen.mbt 生成清单——此处不背具体数字，曾写「21+4」与生成表
// 32 漂移）可脚本化——比逐方法子命令镜像轻一个量级；长活会话（跨命令驻留/
// 前端长连接）仍归 serve 长会话。
//
// 退出码：0=全部帧 ok:true / 1=任一帧 ok:false（**帧 ok 指信封层**顶层
// 位——#400：result 内嵌的 ok 是方法语义位，不算帧失败）/ 4=用法错。
// read_stdin 由薄壳注入（`-` 同款平台绑定）；
// write_stdout 同由薄壳注入（#366：帧出口同步直写——管道口径防截断，
// js/wasm=fs.writeSync / native=fwrite stub，out_line 单源编码）。

///|
pub fn api(
  args : Array[String],
  read_stdin : () -> Bytes,
  write_stdout~ : (Bytes) -> Unit,
  channel~ : EngineChannel,
) -> Int32 {
  ensure_include_reader(channel)
  let mut method_name = ""
  let mut params = "{}"
  let mut batch = false
  // #67（2026-10-11）：help 的第二位置参数是目标方法名（非 params）——
  // api help [method] 形态，单独抓取
  let mut help_target = ""
  let mut i = 0
  while i < args.length() {
    if args[i] == "--batch" {
      batch = true
    } else if args[i].has_prefix("-") {
      // B3 批（2026-11-02，M35 A1）：未知旗标 fail loud——旧解析循环无此臂：
      // 前置形态 `api --xyz ping` 旗标落空静默吞、照常执行 rc=0（病 87 形态
      // ——用户以为旗标生效，零信号）；尾随形态 `api ping --bogus` 被抓进
      // params 位再被下方前缀校验拦下 rc=4、文案却指责 params（旗标误报成
      // params）。run/compile/step 三子命令 2026-10-13 方案 A 已 fail loud，
      // api 独漏在此收口。api 只认 --batch 一个旗标（params 必为 `{` 开头的
      // JSON 对象、方法名不以 `-` 起头——`-` 开头者无合法去处）。
      say("vitro api: 未知旗标：\{args[i]}（api 仅认 --batch）")
      say(
        "用法: api <method> [params-json] | api --batch < frames.ndjson | api help [method]",
      )
      return 4
    } else if method_name == "" {
      method_name = args[i]
    } else if method_name == "help" && help_target == "" {
      help_target = args[i]
    } else if params == "{}" && args[i] != "{}" {
      // 第二个非旗标参数 = params JSON（缺省 "{}"）
      params = args[i]
    }
    i += 1
  }
  // #67：api help——离线可发现性出口。help 是方法位保留字（不进 invoke）：
  // 无 target 打印全方法清单、有 target 打印单方法详情（形状来自 #68
  // serve_param_err 的 expected）；数据 = gateway 生成表 api_help_gen.mbt
  //（权威源 dispatch+serve_param_err，scripts/gen_api_help -check 锁——禁
  // 手抄）。三臂壳全 MoonBit 单源同数据，三臂同形由 vitro_cli_smoke 锁
  //（审阅 v2 S07 P2-1 勘正：原注「wasm 臂同数据（api_help.json）」指向已删
  // 路径——e92fe728 三臂壳全 MoonBit 批）。
  if method_name == "help" && !batch {
    if help_target == "" {
      // 生成文本不带尾换行，out_line 补单尾——与 wasm 壳 write 加换行
      // 逐字节同形（B 组零特例纪律）
      out_line(write_stdout, api_help_list())
      return 0
    }
    return match api_help_detail(help_target) {
      Some(text) => {
        out_line(write_stdout, text)
        0
      }
      None => {
        say(
          "用法错: 未知方法 '\{help_target}'（api help 看方法清单；api help <method> 看详情）",
        )
        4
      }
    }
  } else if method_name == "help" && batch {
    say(
      "用法错: --batch 不与 help 并用（help 是离线出口不进会话）",
    )
    return 4
  }
  // 批式：stdin 全量读入按行切（UTF-8 解码——帧是 JSON 文本域），逐帧
  // invoke——空行跳过（尾换行产物）；id 由 gateway 侧单源处理
  if batch {
    if method_name != "" {
      say(
        "用法错: --batch 不与 <method> 并用（帧序列从 stdin 读）",
      )
      return 4
    }
    let text = @util.utf8_text_partial(read_stdin())
    if text.is_empty() {
      say("用法错: --batch 收到空 stdin（喂 NDJSON 请求帧序列）")
      return 4
    }
    let mut rc = 0
    for line in text.split("\n") {
      let l : String = line.trim(chars=" \t\r").to_owned()
      if l.is_empty() {
        continue
      }
      let resp = (channel.invoke)(l)
      out_line(write_stdout, resp)
      // #400（2026-11-13）：rc 判定走信封层结构化（json_parse_opt + jfield
      // 顶层 ok 位——判定 helper 与 run/step 臂共用；**解析失败处置与
      // run --json 臂同源**〔P3-2 审阅处置批勘正：step/run-文本臂是
      // fail loud rc=1 的不同款〕）。旧 contains 子串宽判定把 run 帧
      // result 内嵌的 "ok":false（run 语义位八字段之一，trap 形态必现）
      // 误当信封失败——三帧信封全 ok 的 UAF trap 序列必假红。解析失败不
      // 记红（帧已透传 stdout，下游自判）+ stderr 留可观测痕迹（#129
      // 通道分立）
      match json_parse_opt(resp) {
        Some(f) => if jfield(f, "ok") is False { rc = 1 }
        None =>
          say(
            "vitro api: 响应帧解析失败（协议破损形态，rc 不受影响——帧已透传）",
          )
      }
    }
    return rc
  }
  if method_name == "" {
    say(
      "用法: api <method> [params-json] | api --batch < frames.ndjson  （例: api memory.regions / api compile '{\"source\":\"int main(){return 0;}\"}'）",
    )
    return 4
  }
  // params 形态校验：必须是 JSON 对象字面量（fail loud——拼错静默当字符串
  // 会拼出非法帧，错误信息更难懂）
  if !params.has_prefix("{") {
    say("用法错: params 须为 JSON 对象字面量，得到 '\{params}'")
    return 4
  }
  // DX P2（#71 工具批，2026-10-11）：未知方法名 cli 层预检 rc=4——此前
  // 落 gateway 报「未知方法」帧 rc=1，shell 脚本会把 rc=1 误读成协议内
  // 失败（compile 错同码位）；名单单源 = gateway dispatch 权威源生成的
  // api_help_detail（None=未知——与 api help 出口同表，禁第二份手抄）。
  if api_help_detail(method_name) is None {
    say(
      "用法错: 未知方法 '\{method_name}'（rc=4 用法错，非协议内失败；api help 看方法清单）",
    )
    return 4
  }
  let resp = (channel.invoke)(
    "{\"id\":1,\"method\":\"\{method_name}\",\"params\":\{params}}",
  )
  out_line(write_stdout, resp)
  // #400：单帧臂同病同修——run 单帧 result 内嵌 ok:false（trap 语义位）
  // 不再误报 rc=1；判定源与 batch 臂同款（信封层结构化；解析失败处置
  // 与 run --json 臂同源——stderr 留痕、rc 不变，P3-2 审阅处置批）
  match json_parse_opt(resp) {
    Some(f) => if jfield(f, "ok") is False { return 1 }
    None =>
      say(
        "vitro api: 响应帧解析失败（协议破损形态，rc 不受影响——帧已透传）",
      )
  }
  0
}
