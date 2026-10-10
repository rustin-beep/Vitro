// stdout 字节直写 stub（2026-10-05 脱钩修复批批一——DIFF-EXIT-STDOUT-
// ENCODE-01 / DIFF-LIB-PUTCHAR-01 销账）：程序 stdout 通道按字节域原样
// 落盘（fwrite），绕开 MoonBit String/println 的 UTF-8 出口编码——≥0x80
// 字节曾双重编码（实测 0xC8 → c3 83 c2 88；Clang 原始字节 80 c8 ff 41，
// putchar_range.c 语料锚）。注入消费：cmd/lib/cli 的 run（write_stdout
// 参数——lib 包零 native 依赖，同 clock/read_stdin 注入模式）。
// 与 cmd/vitro 的 stdout_stub.c 同源复制连坐（native-stub 禁 ../；
// 机判红线见 scripts/moonbit/single_source 条目 stdout_stub_copies）。
#include <stdio.h>
#include "moonbit.h"

MOONBIT_FFI_EXPORT void moonbit_vitro_write_stdout(moonbit_bytes_t b) {
  int32_t len = Moonbit_array_length(b);
  if (len > 0) {
    fwrite(b, 1, (size_t)len, stdout);
  }
}
