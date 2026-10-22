// cmd/lib/cli·顶层用法单源（#215，2026-10-22）：print_help 此前在
// cmd/vitro 与 cmd/vitro_js 两壳各抄一份（文案连坐两处改——--realtime
// 批即双改）；通道纪律（#129/#215）：显式 help/--help = stdout（rc=0，
// 管道友好）；无参/未知命令/用法错语境的帮助 = stderr（rc=4——spec §1
// 「stdout 只承载程序输出」+「rc=4 路径 stdout 恒为空」不变式，
// vitro_cli_smoke 锚定）。

///|
/// 顶层用法文本（子命令总览——多行，**行间 \n、尾行不带**——println 补尾）。
pub fn usage_text() -> String {
  let b = StringBuilder()
  b.write_string("用法: vitro <cmd> [args]\n")
  b.write_string(
    "  run <file.c> [--json] [--realtime] [--dump-memory out] [-i in] [-- <argv...>]   编译+执行（退出码 0/1/2/3/4；--json=事件流 NDJSON；--realtime=time()/clock() 真墙钟，默认确定性判分）\n",
  )
  b.write_string(
    "  compile <file.c | -> [--json]                             编译+诊断单出\n",
  )
  b.write_string(
    "  step <file.c | -> [--max-steps N] [--json|--summary]      一次性 step 流（交互调试走 serve）\n",
  )
  b.write_string(
    "  api <method> [params-json] | api --batch < frames.ndjson  万能单帧 + 批式多帧（状态跨帧保留——seek/breakpoints/input.feed 序列可脚本化；响应 NDJSON 直出；任一帧 ok:false → rc=1；api help <method> 看参数详情）\n",
  )
  b.write_string(
    "  help                                                      本帮助",
  )
  b.to_string()
}

///|
/// 打印顶层用法：`to_stderr=true` 走 stderr（无参/未知命令——rc=4 用法
/// 错语境，#215）；false = stdout（显式 help——rc=0，管道友好）。
pub fn print_usage(to_stderr : Bool) -> Unit {
  let text = usage_text()
  if to_stderr {
    cli_stderr_write(@utf8.encode(text + "\n"))
  } else {
    println(text)
  }
}
