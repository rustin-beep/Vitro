// @category: baseline
// 对抗批挖出（2026-10-19）：struct 成员声明的逗号后跟类型名 = 重复声明
// 说明符（`int a, int b`）非法 C，clang "expected member name or ';'"；
// vitro 旧形态把类型 token 当声明器名误收，修后 E2005。对照组合法
// 多声明器（`int a, b;`）与分号分隔两声明零误报。
#include <stdio.h>
struct S { int a, int b; };
int main(void) {
  struct S s = {0};
  printf("%d\n", s.a + s.b);
  return 0;
}
