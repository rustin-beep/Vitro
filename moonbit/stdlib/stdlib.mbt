///|
/// 标准库头文件清单（P1 面）——**名单唯一真源**（方案 A · 设计稿 §3.6：
/// 取代 `gen_stubs` 硬编码 `stubNames`）。
///
/// 消费方（P1 起）：`scripts/moonbit/gen_stubs`（Go）解析本数组驱动生成
/// `lexer/internal/host/stubs_gen.mbt`，并与 `libc_src/include/` 目录做
/// **集合对账**（目录多出未登记头 / 登记名无对应文件均 fail loud）——此即
/// 「headers 三方一致闸」的 P1 版两面；第三面（`capabilities.libraries`
/// JSON 出口供 Go 侧对账）随 P3 接线闭环。引擎内消费（lexer `<>` 判定等）
/// 随 P2~P4 逐面接入。
///
/// **顺序冻结**：本数组序 = Rust `resolver.rs load_stub` 的 match 序（历史
/// 序）——它决定 `stubs_gen.mbt` 的 match 臂序与源 sha256 拼接序（P1 验收线
/// = 产物逐字节一致），**勿按字典序重排**；增删头文件 = 改本数组 + 加/删
/// `libc_src/include/` 对应文件 + 重跑 gen_stubs。
pub fn headers() -> Array[String] {
  [
    "stdio.h", "stdlib.h", "ctype.h", "math.h", "string.h", "stdarg.h", "limits.h",
    "stdbool.h", "stddef.h", "stdint.h", "time.h", "assert.h", "errno.h", "float.h",
  ]
}
