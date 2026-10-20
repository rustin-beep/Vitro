// @category: baseline
// #154 红锚：typedef 用不同类型重定义同一名字（C23 §6.7p3 约束——仅当
// 指向同一类型才合法）必须诊断——clang/gcc error "redefinition of
// typedef"；vitro 修后 E3077。对照组同类型重复 typedef 合法（零诊断）。
#include <stdio.h>
typedef int T;
typedef double T;      /* 非法：不同类型重定义 */
typedef int SameT;
typedef int SameT;     /* 合法：同类型重定义（C23 起） */
int main(void) {
  SameT v = 1;
  printf("%d\n", v);
  return 0;
}
