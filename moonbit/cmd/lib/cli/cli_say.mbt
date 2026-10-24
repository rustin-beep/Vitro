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
/// 用法错文案的 stderr 出口（#215 pub 化——三壳〔vitro/vitro_js/
/// vitro_wasm〕的顶层分派〔无参/未知命令/独立 exe 指引〕此前 println
/// 走 stdout，违 spec §1「rc=4 路径 stdout 恒为空」；单源收口供壳调用）。
pub fn usage_err(s : String) -> Unit {
  say(s)
}
