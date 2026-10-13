#include <stdio.h>

// @category: #71 台账批D·除零文案作用域过滤（病 53，2026-10-13）——
// 除零发生在 main 帧时，inspect 段只列本帧零值变量（divisor）；旧扫全
// 符号表把 other 帧的 far_var 借 main 帧 locals_base 错位读值列出
//（错作用域+错值双错，oracle 同病 S9 脱钩修正）。病 52 同批：LL 数组
// 反算步长表对齐 observe 同族（wbtest 单点锚）。
// 运行期 divide-zero trap：Vitro 白箱教学 trap vs Clang Windows SEF 崩——
// known_direct 登记（array_bound_const_index 同款形态）。

int other(int z) {
  int far_var = 0;
  return z + far_var;
}

int main() {
  int local_main = 7;
  int r = other(local_main);
  int divisor = 0;
  printf("%d\n", r / divisor);
  return 0;
}
