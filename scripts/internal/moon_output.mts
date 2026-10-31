// moon_output.mts —— Moon 侧两流合流器单源（#394 审阅 P3-② 下沉，
// 2026-10-31）：原落 diff_gate/targets/vm.mts，被 clang_direct 跨驱动
// import（targets 模块跨驱动依赖的结构债）——下沉 internal 供防线共消费。
// Go 双轨（clang_direct/main.go）无从 import TS，同款内联（头部互指注释）。

/**
 * Moon 侧两流合流（#129 后标记行走 stderr）：剥壳层 backend 标注行，
 * stderr 逐行续接。
 * #207 补行退役适配（2026-10-31）：文本模式 stdout 原样零修饰后末行可
 * 无换行——续接前补边界换行，否则 stderr 首行（`// NOTE` 完成附注每例
 * 必有）与 stdout 末行粘连成行，extractMoonBitStdout 的标记行剥除失效
 * （修前 760 例 vm diff 302 例红实锤）。
 * #394 审阅 P2-1 幂等化（2026-10-31）：CLI 侧（cli_frame.mbt
 * stderr_boundary_newline）已单源负责两流边界——stdout 无尾换行时首条
 * stderr 标记行前自带 1 字节 `\n`。本函数对「stderr 自带前导换行」的
 * 新形态**不再补 stdout 边界**（恒双补会多一空行）；stderr 为空等旧
 * 形态仍由本函数兜底。产出与 P2-1 前逐字节一致——vm diff golden 零重冻。
 * 注意：返回值**尾部恒多一个空行**（stderr split 的尾空串元素各续接
 * `\n` 的自然产物，Go/mts 同形态）——依赖调用方 extractMoonBitStdout
 * 的尾部空行剥除归一吸收，勿在中间消费。
 */
export function mergeMoonOutput(stdout: string, stderr: string): string {
  let text = stdout;
  if (text.length > 0 && !text.endsWith("\n") && !stderr.startsWith("\n")) text += "\n";
  for (const line of stderr.split("\n")) {
    if (line.startsWith("[vitro] backend=")) continue;
    text += line + "\n";
  }
  return text;
}
