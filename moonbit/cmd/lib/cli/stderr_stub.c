// stderr 字节直写 stub（#129 通道分立批，2026-10-16）：文本面的诊断行/
// note/标记行/用法错文案走 stderr（#69 翻案——用户拍板 stdout 只承载
// 被测程序输出）。与 cmd/vitro 的 stdout_stub.c 同款 Bytes 直写形态
// （fwrite 绕开 println 的 stdout 出口——stderr 通道无 Latin-1 字节域
// 需求，UTF-8 文本即可）。
#include <stdio.h>
#include "moonbit.h"

MOONBIT_FFI_EXPORT void moonbit_vitro_cli_write_stderr(moonbit_bytes_t b) {
  int32_t len = Moonbit_array_length(b);
  if (len > 0) {
    fwrite(b, 1, (size_t)len, stderr);
  }
}
