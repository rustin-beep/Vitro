// @category: baseline
// #157 红锚：柔性数组成员用聚合初始化器静态初始化（C23 约束违反）
//——clang error "initialization of flexible array member is not
// allowed"；vitro 修后 E3079。对照组：柔性成员运行时写入合法
//（malloc 式用法教学面——本例用指针别名写）。
#include <stdio.h>
#include <stdlib.h>
struct S { int n; int d[]; };
int main(void) {
  struct S s = { 3, {1, 2, 3} };   /* 非法：柔性成员不可初始化 */
  printf("%d\n", s.n);
  return 0;
}
