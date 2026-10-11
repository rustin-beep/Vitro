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
// 全部 21+4 协议方法（含 dump 族/memory/output.delta/session 族）可脚本化
// ——比 21 个子命令镜像轻一个量级；长活会话（跨命令驻留/前端长连接）仍归
// serve 长会话。
//
// 退出码：0=全部帧 ok:true / 1=任一帧 ok:false（协议内错误统一——api 是
// 透传层不细分语义）/ 4=用法错。read_stdin 由薄壳注入（`-` 同款平台绑定）。

///|
pub fn api(args : Array[String], read_stdin : () -> Bytes) -> Int {
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
    } else if !args[i].has_prefix("-") && method_name == "" {
      method_name = args[i]
    } else if method_name == "help" && !args[i].has_prefix("-") && help_target == "" {
      help_target = args[i]
    } else if method_name != "" && params == "{}" && args[i] != "{}" {
      // 第二个非旗标参数 = params JSON（缺省 "{}"）
      params = args[i]
    }
    i += 1
  }
  // #67：api help——离线可发现性出口。help 是方法位保留字（不进 invoke）：
  // 无 target 打印全方法清单、有 target 打印单方法详情（形状来自 #68
  // serve_param_err 的 expected）；数据 = gateway 生成表 api_help_gen.mbt
  //（权威源 dispatch+serve_param_err，scripts/gen_api_help -check 锁——禁
  // 手抄）。wasm 臂同数据（api_help.json），双臂同形由 vitro_cli_smoke 锁。
  if method_name == "help" && !batch {
    if help_target == "" {
      // 生成文本不带尾换行，println 补单尾——与 wasm 壳 write 加换行
      // 逐字节同形（B 组零特例纪律）
      println(@gateway.api_help_list())
      return 0
    }
    return match @gateway.api_help_detail(help_target) {
      Some(text) => {
        println(text)
        0
      }
      None => {
        println(
          "用法错: 未知方法 '\{help_target}'（api help 看方法清单；api help <method> 看详情）",
        )
        4
      }
    }
  } else if method_name == "help" && batch {
    println("用法错: --batch 不与 help 并用（help 是离线出口不进会话）")
    return 4
  }
  // 批式：stdin 全量读入按行切（UTF-8 解码——帧是 JSON 文本域），逐帧
  // invoke——空行跳过（尾换行产物）；id 由 gateway 侧单源处理
  if batch {
    if method_name != "" {
      println(
        "用法错: --batch 不与 <method> 并用（帧序列从 stdin 读）",
      )
      return 4
    }
    let text = @util.utf8_text_partial(read_stdin())
    if text.is_empty() {
      println(
        "用法错: --batch 收到空 stdin（喂 NDJSON 请求帧序列）",
      )
      return 4
    }
    let mut rc = 0
    for line in text.split("\n") {
      let l : String = line.trim(chars=" \t\r").to_owned()
      if l.is_empty() {
        continue
      }
      let resp = @gateway.invoke(l)
      println(resp)
      if resp.contains("\"ok\":false") {
        rc = 1
      }
    }
    return rc
  }
  if method_name == "" {
    println(
      "用法: api <method> [params-json] | api --batch < frames.ndjson  （例: api memory.regions / api compile '{\"source\":\"int main(){return 0;}\"}'）",
    )
    return 4
  }
  // params 形态校验：必须是 JSON 对象字面量（fail loud——拼错静默当字符串
  // 会拼出非法帧，错误信息更难懂）
  if !params.has_prefix("{") {
    println(
      "用法错: params 须为 JSON 对象字面量，得到 '\{params}'",
    )
    return 4
  }
  let resp = @gateway.invoke(
    "{\"id\":1,\"method\":\"\{method_name}\",\"params\":\{params}}",
  )
  println(resp)
  if resp.contains("\"ok\":false") {
    return 1
  }
  0
}
