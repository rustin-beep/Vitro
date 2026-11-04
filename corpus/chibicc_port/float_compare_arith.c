// @category: chibicc_port
// source: chibicc test/float.c（MIT, © 2019 Rui Ueyama）
// topic: 浮点比较/NaN 不等性/浮点四则赋值截断/浮点逻辑非与条件（!0. = 1 面）
#include <stdio.h>
int main(void) {
  printf("%d %d %d\n", 2e3==2e3, 2e3==2e5, 2.0==2);
  printf("%d %d %d\n", 5.1<5, 5.0<5, 4.9<5);
  printf("%d %d %d\n", 5.1<=5, 5.0<=5, 4.9<=5);
  printf("%d %d\n", 2e3f==2e3, 2e3f==2e5);
  printf("%d %d\n", 2.0f==2, 5.1f<5);
  printf("%d %d\n", 5.0f<=5, 4.9f<=5);
  printf("%d\n", 0.0/0.0 == 0.0/0.0);   // 0（NaN != NaN）
  printf("%d\n", 0.0/0.0 != 0.0/0.0);   // 1
  printf("%d %d %d %d\n", 0.0/0.0 < 0, 0.0/0.0 <= 0, 0.0/0.0 > 0, 0.0/0.0 >= 0);
  int a = 2.3+3.8;  printf("%d\n", a);   // 6
  int b = 2.3-3.8;  printf("%d\n", b);   // -1
  int c = -3.8;     printf("%d\n", c);   // -3
  int d = 3.3*4;    printf("%d\n", d);   // 13
  int e = 5.0/2;    printf("%d\n", e);   // 2
  int f = 2.3f+3.8f; printf("%d\n", f);  // 6
  int g = 2.3f+3.8;  printf("%d\n", g);  // 6
  int h = 2.3f-3.8;  printf("%d\n", h);  // -1
  int i2 = -3.8f;    printf("%d\n", i2); // -3
  int j = 3.3f*4;    printf("%d\n", j);  // 13
  int k = 5.0f/2;    printf("%d\n", k);  // 2
  // 注：chibicc 原 !3./!0. 与 !3.f/!0.f——clang 0 1 / Vitro 1 1 与（! 浮点操作数判零截断，
  // 速查表 Z 族扩展格：!3.0 误判为零，DIFF 候选），移 deferred
  return 0;
}
