// stdout 字节直写 stub（2026-10-05 脱钩修复批批一——DIFF-EXIT-STDOUT-
// ENCODE-01 / DIFF-LIB-PUTCHAR-01 销账）：程序 stdout 通道按字节域原样
// 落盘（fwrite），绕开 MoonBit String/println 的 UTF-8 出口编码——≥0x80
// 字节曾双重编码（实测 0xC8 → c3 83 c2 88；Clang 原始字节 80 c8 ff 41，
// putchar_range.c 语料锚）。注入消费：cmd/lib/cli 的 run（write_stdout
// 参数——lib 包零 native 依赖，同 clock/read_stdin 注入模式）。
// 与 cmd/vitro 的 stdout_stub.c 同源复制连坐（native-stub 禁 ../；
// 机判红线见 scripts/moonbit/single_source 条目 stdout_stub_copies）。
// #315（2026-10-26）：Windows CRT 文本模式把 fwrite 的每个 \n 静默改写
// 成 \r\n——native 臂 stdout 与 js/wasm 逐字节不同形（每换行 +1B）且与
// 自身 --json delta 通道（引擎内存字节）不同形。首次调用切 stdout 二进
// 制模式（POSIX 无此概念，_WIN32 隔离）；CLI_PROTOCOL_V1 §1「字节直写
// 无 CRLF 转换」承诺自此在 Windows 上成立。
// #357（2026-10-30）：fwrite 后即刷 + SIGABRT 崩溃路径刷出——重定向/管道
// 下 stdout 对非 tty 全缓冲（glibc/UCRT 同），stderr 标记行（无缓冲）反超
// 程序输出致 `> f 2>&1` 合并流错序；panic→abort 不刷 stdio 缓冲致诊断
// 蒸发（双流 0 字节 + rc=134 静默崩溃）。两防线均落本 stub。
#include <stdio.h>
#include <signal.h>
#include "moonbit.h"
#ifdef _WIN32
#include <io.h>
#include <fcntl.h>
#endif

/* #357（2026-10-30）：崩溃路径防线——MoonBit 运行时 panic 走 abort，而
 * glibc/UCRT 的 abort 不刷 stdio 缓冲：重定向下 panic 诊断（runtime 打印
 * 走 stdout）连同未刷输出一并蒸发。先 fflush(NULL) 刷全部输出流再恢复
 * 默认处置并 re-raise——进程仍死于 SIGABRT（shell 视角 134 / core dump
 * 语义保真）。strict POSIX 下 fflush 非 async-signal-safe，但 SIGABRT 是
 * 同步 raise、栈完好，工程惯例可靠。诊断通道归属（panic 文案在 stdout
 * 而非 stderr）是 moon runtime 上游行为，本仓不可治——此处只保「不蒸发」。
 * 触发面现状：#363 批后 invalid UTF-8 已 U+FFFD 折回不再 panic，本防线
 * 面向未来 panic（数组越界等引擎缺陷场景）。MSVC 兼容：signal/SIGABRT/
 * SIG_DFL 均标准 C（#335 注记——stub 编译链固定 MSVC 探测，GNU 属性不可
 * 用，本形态纯 C89）。 */
static void vitro_abort_flush(int sig) {
  (void)sig;
  fflush(NULL);
  signal(SIGABRT, SIG_DFL);
  raise(SIGABRT);
}

/* #335（2026-10-27）：帧通道行尾治本——CLI 帧通道（MoonBit println 出口：
 * compile/step/api/serve 的响应帧）不走本 stub 的 fwrite，Windows CRT 文本
 * 模式把 println 的每个 \n 静默改写 \r\n（native 帧尾 0d 0a vs js/wasm
 * 0a）。进程启动早期（main.mbt 首行）调用本导出把 stdout/stderr 双 fd
 * 切二进制；stdin 不切——serve 的 fgets 行读取面维持 CRT 折行 + 手剥
 * \r\n 既有归一。POSIX 无此概念。
 * **不用 __attribute__((constructor))**：moon test --target native 的 stub
 * 编译链固定 MSVC 探测（MOON_CC=clang 不覆盖——2026-10-27 实测 C2143/
 * C2091 编译红），GNU 属性不可移植；显式导出 + main 首行调用双编译器
 * 兼容。幂等：重复调用无副作用（与下方首次调用切换语义叠加无害）。
 * #357（2026-10-30）：同点挂 SIGABRT handler（三薄壳 main 首行皆调本
 * 导出——单一挂点覆盖 cmd/run、cmd/vitro、cmd/step 全部 native 壳）。 */
MOONBIT_FFI_EXPORT void moonbit_vitro_ensure_binary_mode(void) {
  static int done = 0;
  if (!done) {
#ifdef _WIN32
    _setmode(_fileno(stdout), _O_BINARY);
    _setmode(_fileno(stderr), _O_BINARY);
#endif
    signal(SIGABRT, vitro_abort_flush);
    done = 1;
  }
}

MOONBIT_FFI_EXPORT void moonbit_vitro_write_stdout(moonbit_bytes_t b) {
  static int stdout_binary = 0;
  /* _setmode 失败（无效 fd——实际不可达）返回 -1 静默退回文本模式：
     C stub 无诊断通道，fail-loud 无出口（P3-3 审阅注记） */
  if (!stdout_binary) {
#ifdef _WIN32
    _setmode(_fileno(stdout), _O_BINARY);
#endif
    stdout_binary = 1;
  }
  int32_t len = Moonbit_array_length(b);
  if (len > 0) {
    fwrite(b, 1, (size_t)len, stdout);
    /* #357（2026-10-30）：fwrite 后即刷——重定向/管道下 stdout 对非 tty
     * 全缓冲，stderr 标记行（无缓冲）反超程序输出：`> f 2>&1` 合并流里
     * // STDERR // NOTE 抢在 printf 输出之前（js/wasm 臂出口同步写无此
     * 病）。逐写即刷后与 stderr 的相对序由写出序决定——三臂同形。代价：
     * stdout 从「进程退出一次刷」变逐次刷——run 的 stdout 是 run 结束后
     * 的批量导出 + 帧序列（行协议语义），本就无中途吞吐收益。 */
    fflush(stdout);
  }
}
