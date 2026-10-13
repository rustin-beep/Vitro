#include <stdio.h>

// @category: #71 台账批B·typeck 假阳性/缺口五病锚（2026-10-13 修复批）——
// union 数组元素初始化（55，typeck check_array_elem_value 扩 TK_Union +
// codegen emit_local_array_init 嵌套臂同扩两层连动）/ 三目空指针常量
// 豁免（57，C11 §6.5.15p5）/ int x = x 自引用（58，Clang -O0 干净）/
// long long←double 窄化臂（60，对齐 -Wliteral-conversion）/ 1ULL<<63
// 恒 ULL 定型（62，u+ll 后缀词法 ll 分量不丢）。

union U { int i; char b[4]; };

int main() {
  union U us[2] = {{1}, {2}};
  printf("%d\n", us[0].i + us[1].i);
  int* p = 0;
  int v = 1;
  int* q = v ? p : 0;
  printf("%d\n", q == 0);
  int x = x;
  printf("%d\n", x == x);
  long long y = 3.14;
  printf("%lld\n", y);
  unsigned long long big = 1ULL << 63;
  printf("%llu\n", big >> 62);
  return 0;
}
