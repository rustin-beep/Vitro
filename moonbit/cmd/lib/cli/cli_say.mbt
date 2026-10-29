// cmd/lib/cli·say（#129 通道分立批，2026-10-16）：文本面的 stderr 出口
// ——诊断三级行/FIX/COMPILE-OK/STDERR/NOTE/TRAP/EXIT 标记行/用法错文案
// 全走本函数（#69 混流裁定翻案：用户拍板 stdout 只承载被测程序输出，
// 字节精确——gcc/clang 先例）。json 模式事件流与 api 子命令的帧输出
// 仍是 stdout（机器读协议面，spec §4/§6 在册承诺，不动）。

///|
/// stderr 文本行（UTF-8 编码 + 尾换行——println 的 stderr 对偶）。
fn say(s : String) -> Unit {
  cli_stderr_write(@utf8.encode(s + "\n"))
}

///|
/// stdout 协议帧行（UTF-8 编码 + 尾换行——与 println 逐字节同形）。
/// #366（2026-10-28）：api/step/json 模式帧出口统一改走壳注入的同步
/// write 通道——此前 println 在 js/wasm 臂落到 node process.stdout.write，
/// 对**管道**是异步写（对文件同步），帧序列打完立即 process.exit 会丢弃
/// 未刷写队列：>1MB 帧管道口径静默截断（WSL 实测 pipe 65808B/146448B vs
/// file 1398439B，rc=0 零信号、产出非法 JSON）；native 臂 CRT exit 刷
/// 缓冲不受影响。注入通道与 run 子命令的 write_stdout 同款（js/wasm =
/// fs.writeSync(1)、native = stdout_stub fwrite），出口原语自此单源。
/// 不迁通道面：print_usage 用法文本（单笔小写入，管道内核缓冲即完）与
/// serve 流式（事件循环自然排空、无 exit 竞争）仍走 println。
fn out_line(write_stdout : (Bytes) -> Unit, s : String) -> Unit {
  write_stdout(@utf8.encode(s + "\n"))
}

///|
/// 用法错文案的 stderr 出口（#215 pub 化——三壳〔vitro/vitro_js/
/// vitro_wasm〕的顶层分派〔无参/未知命令/独立 exe 指引〕此前 println
/// 走 stdout，违 spec §1「rc=4 路径 stdout 恒为空」；单源收口供壳调用）。
pub fn usage_err(s : String) -> Unit {
  say(s)
}
