// stderr 字节直写 stub（#129 通道分立批，2026-10-16）：文本面的诊断行/
// note/标记行/用法错文案走 stderr（#69 翻案——用户拍板 stdout 只承载
// 被测程序输出）。与 cmd/vitro 的 stdout_stub.c 同款 Bytes 直写形态
// （fwrite 绕开 println 的 stdout 出口——stderr 通道无 Latin-1 字节域
// 需求，UTF-8 文本即可）。
// #315（2026-10-26）：Windows CRT 文本模式把 fwrite 的每个 \n 静默改写
// 成 \r\n——native 臂 stderr（TRAP 教学文案、// NOTE 等标记行）每换行
// +1B，按行切分的下游会把 \r 留在值里；stderr 走发布包内文件、下游
// 无法自写 stub 规避，必须在包内治。首次调用切 stderr 二进制模式
// （POSIX 无此概念，_WIN32 隔离）。
#include <stdio.h>
#include "moonbit.h"
#ifdef _WIN32
#include <io.h>
#include <fcntl.h>
#endif

MOONBIT_FFI_EXPORT void moonbit_vitro_cli_write_stderr(moonbit_bytes_t b) {
  static int stderr_binary = 0;
  /* _setmode 失败（无效 fd——实际不可达）返回 -1 静默退回文本模式：
     C stub 无诊断通道，fail-loud 无出口（P3-3 审阅注记） */
  if (!stderr_binary) {
#ifdef _WIN32
    _setmode(_fileno(stderr), _O_BINARY);
#endif
    stderr_binary = 1;
  }
  int32_t len = Moonbit_array_length(b);
  if (len > 0) {
    fwrite(b, 1, (size_t)len, stderr);
  }
}
