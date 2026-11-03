// @category: chibicc_port
// source: chibicc test/arith.c（MIT, © 2019 Rui Ueyama）— ASSERT 形态 port
// topic: 位运算/取反/逻辑非/取模/移位常量边界 + 三元类型面
// ID 域披露（审阅 P3-3）：`%d %lld` 行把 LLP64 的 long（4B）传给 %lld——Win ABI
// 变参按 8 字节槽零扩展巧合成立；保持 chibicc 原形态（Win clang 同口径实跑锁值），
// LP64 平台该行天然同值（long=8B），跨口径重跑时留意
#include <stdio.h>
int main(void) {
  printf("%d %d %d %d\n", !1, !2, !0, !(char)0);
  printf("%d %d\n", !(long)3, sizeof(!(char)0));
  printf("%d %d\n", ~0, ~-1);
  printf("%d %lld\n", 17%6, ((long)17)%6);
  printf("%d %d %d %d\n", 0&1, 3&1, 7&3, -1&10);
  printf("%d %d\n", 0|1, 0b10000|0b00011);
  printf("%d %d\n", 0^0, 0b1111^0b1111);
  printf("%d\n", 0b110100 == (0b111000^0b001100));
  printf("%d %d %d %d\n", 1<<0, 1<<3, 5<<1, 5>>1);
  printf("%d\n", -1>>1);
  printf("%d %d\n", 0?1:2, 1?1:2);
  printf("%d %d\n", 0?-2:-1, 1?-2:-1);
  printf("%d\n", (int)sizeof(0?1:2));
  // 注：chibicc 原 sizeof(1?(long)2:(char)3)——Win 4 / LP64 8 平台方言（sizeof_types_llp64 已锁 Win 口径），此行不 port
  printf("%lld %lld\n", (long long)(0?(long)-2:-1), (long long)(0?-2:(long)-1));
  return 0;
}
