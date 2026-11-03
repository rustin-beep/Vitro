// @category: chibicc_port
// source: chibicc test/string.c（MIT, © 2019 Rui Ueyama）
// topic: 字符串转义（ASCII 域）与拼接：简单转义/八进制/十六进制<0x80/字面串联/NUL 终止（≥0x80 hex 转义属 \xE4 计长差异面，见 deferred）
#include <stdio.h>
#include <string.h>
int main(void) {
  printf("%d %d\n", ""[0], (int)sizeof(""));
  printf("%d %d %d %d\n", "abc"[0], "abc"[1], "abc"[2], "abc"[3]);
  printf("%d\n", (int)sizeof("abc"));
  printf("%d %d %d %d %d %d\n", "\a"[0], "\b"[0], "\t"[0], "\n"[0], "\v"[0], "\f"[0]);
  printf("%d\n", "\r"[0]);
  // 注：chibicc 原支持 \e（GNU 扩展=27）——Vitro 静默按 'e'=101 解析（fail loud 缺失，DIFF 候选），移 deferred
  printf("%d\n", "\ax\ny"[1]);             // 120
  printf("%d %d %d\n", "\0"[0], "\20"[0], "\101"[0]);  // 0 16 65
  printf("%d %d\n", "\1500"[0], "\x00"[0]);  // 104 0
  printf("%d\n", "\x77"[0]);               // 119（<0x80 安全域）
  printf("%d\n", (int)sizeof("abc" "def"));   // 7
  printf("%d\n", (int)sizeof("abc" "d" "efgh"));  // 9
  printf("%d %d\n", strcmp("abc" "d" "\nefgh", "abcd\nefgh") == 0,
         strcmp("abcd\nefgh", "abc" "d" "\nefgh") == 0);
  printf("%d\n", strcmp("\x9" "0", "\t0") == 0);  // hex 后接字符串字面量分界
  return 0;
}
