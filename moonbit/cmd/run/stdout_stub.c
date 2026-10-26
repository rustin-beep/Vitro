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
#include <stdio.h>
#include "moonbit.h"
#ifdef _WIN32
#include <io.h>
#include <fcntl.h>
#endif

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
  }
}
