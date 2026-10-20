// @category: baseline
// #182 D-5 红锚：struct 内函数类型成员（C11 6.7.2.1p5 约束——"field
// declared as a function"）clang/gcc 双 error；vitro 旧形态静默把成员
// 函数声明器衰减成函数指针误收，修后 parser 声明器树层判 E3082。
// 对照组：显式函数指针成员 int (*fp)(void) 合法（interpret 后同形，
// 判定在树层区分源形态）。
#include <stdio.h>
struct S { int v; int f(void); };
int main(void) {
  struct S x;
  struct FP { int v; int (*fp)(void); } fpx;
  x.v = 1;
  fpx.v = 2;
  printf("%d %d\n", x.v, fpx.v);
  return 0;
}
