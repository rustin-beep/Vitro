// @category: chibicc_port
// source: chibicc test/varargs.c（MIT, © 2019 Rui Ueyama）— vsprintf/va_copy 面拆出（见 deferred S7）
// topic: va_arg 整数链/浮点整型混合链（vprintf 族 %s ≥4 字节栈下溢缺陷面不进本文件）
#include <stdio.h>
#include <stdarg.h>
int sum1(int x, ...) {
  va_list ap;
  va_start(ap, x);
  for (;;) {
    int y = va_arg(ap, int);
    if (y == 0) return x;
    x += y;
  }
}
int sum2(int x, ...) {
  va_list ap;
  va_start(ap, x);
  for (;;) {
    double y = va_arg(ap, double);
    x += (int)y;
    int z = va_arg(ap, int);
    if (z == 0) return x;
    x += z;
  }
}
int main(void) {
  printf("%d\n", sum1(1, 2, 3, 0));
  printf("%d\n", sum1(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 0));
  printf("%d\n", sum2(1, 2.0, 3, 4.0, 5, 6.0, 0));
  // 注：chibicc 原 ASSERT(210, sum2(1,2.0,...,20.0,0))（20 对变参长链）——Vitro E3087 变参区越界 trap
  //（M17「变参 64B」族缺陷面），移 deferred（修复后入库批候选）
  return 0;
}
