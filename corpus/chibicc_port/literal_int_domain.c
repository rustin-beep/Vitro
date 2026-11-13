// @category: chibicc_port
// source: chibicc test/literal.c（MIT, © 2019 Rui Ueyama）
// topic: 整数字面量：八/十/十六/二进制、U/L/LL 后缀域、64 位边界值、无符号移位（Win LLP64 口径）
#include <stdio.h>
int main(void) {
  printf("%d %d %d\n", 0777, 0x0, 0xa);
  printf("%d %d\n", 0XA, 0xbeef);
  printf("%d\n", 0xBEEF == 48879);
  printf("%d %d %d\n", 0b0, 0b1, 0b101111);   // 二进制字面量（C23/扩展）
  printf("%d\n", 0B101111 == 47);
  printf("%d\n", (int)sizeof(0));
  // 注：chibicc 原 sizeof(0L)/sizeof(0LU)/sizeof(0UL) → Win clang 4（LLP64 long=4）——Vitro 8
  //（L/UL 后缀字面量统一入 8 字节域，后缀域 DIFF 候选；sizeof(long) 类型面 4 由 sizeof_types_llp64 锁），移 deferred
  printf("%d %d\n", (int)sizeof(0LL), (int)sizeof(0LLU));
  printf("%d %d\n", (int)sizeof(2147483647), (int)sizeof(2147483648));  // 4 8
  printf("%d\n", (int)(0xffffffffffffffff == -1LL));  // ULL 域截断比较
  printf("%d\n", (int)sizeof(0xffffffffffffffff));    // 8
  printf("%d %d\n", (int)sizeof(4294967295U), (int)sizeof(4294967296U)); // 4 8
  printf("%d\n", -1U>>30);           // 3
  // 注：chibicc 原 64 位移位族（-1ull>>62 / 0xffffffffffffffff>>63 等）——Vitro LShr 移位量上限 31 触发 trap
  //（「移位量越界：62（必须是 0~31）」——移位量域绑 int 宽度，LL 移位 DIFF 候选），整族移 deferred
  printf("%lld\n", 01777777777777777777777);  // 八进制 64 位
  printf("%d\n", 0x1ffffffff > 0);   // 8 字节域
  printf("%d\n", (int)sizeof(0x1ffffffff));   // 8
  printf("%d\n", (int)sizeof(0xffffffff));    // 4
  printf("%d\n", 0xffffffff>>31);    // 1
  printf("%d %d\n", (int)sizeof(040000000000), (int)sizeof(037777777777));
  printf("%d\n", 1 << 31 >> 31);     // -1
  printf("%d\n", 0x1 << 31 >> 31);
  printf("%d\n", 0b1 << 31 >> 31);
  printf("%d %d\n", (int)sizeof(8.0f), (int)sizeof(0.3F));   // 4 4
  printf("%d %d\n", (int)sizeof(0.), (int)sizeof(.0));     // 8 8
  printf("%d %d\n", (int)'a', (int)'\n');
  // #510 修复翻面转正（2026-11-13）：chibicc 原 '\x80' → -128（char 符号域）
  // ——旧 Vitro 128（hex 字面量 ≥0x80 零扩展）曾移 deferred；scanner 符号化
  // 修复后两侧一致，探针转正为锚
  printf("%d\n", (int)'\x80');
  return 0;
}
