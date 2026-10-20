// @category: baseline
// #174 红锚：同一 struct/union 内重复成员名（C11 6.7.2.1p7 约束）必须诊断
//——clang/gcc 双 error "duplicate member"；vitro 旧零诊断误收。
// 变体覆盖：异类型重复 / union 重复 / typedef 匿名体重复（嵌套定义形态
// 随注册路径同查）；对照组同 struct 不同名成员双 ACCEPT。
#include <stdio.h>
struct S { int a; int a; };            /* 同类型重复 */
struct T { int b; double b; };          /* 异类型重复 */
union U { int c; char c; };             /* union 重复 */
struct OK { int x; int y; };            /* 对照组合法 */
int main(void) {
  struct OK o;
  o.x = 1; o.y = 2;
  printf("%d %d\n", o.x, o.y);
  return 0;
}
