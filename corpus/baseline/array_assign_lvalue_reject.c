// @category: baseline
// #175 红锚：数组名作赋值左值（不可修改左值，C11 6.5.16p2 约束）必须诊断——
// clang: array type is not assignable / gcc: assignment to expression with
// array type 双 error；vitro 旧零诊断误收。修后双侧编译失败判 match。
// 变体覆盖：数组名=指针 / 数组名=数组名；对照组 p = a（合法 decay）双 ACCEPT。
#include <stdio.h>
int main(void) {
  int a[3] = {1, 2, 3};
  int b[3] = {4, 5, 6};
  int *p = a; /* 合法：数组 decay 给指针（对照组） */
  a = p;      /* 非法：数组整体赋值 */
  b = a;      /* 非法：数组名 = 数组名 */
  printf("%d %d\n", a[0], p[0]);
  return 0;
}
