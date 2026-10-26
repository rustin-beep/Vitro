// @category: baseline
// #334 红锚：struct/union 成员声明带存储类说明符必须诊断（C11 6.7.2.1p1）——
// clang: type name does not allow storage class to be specified / gcc 同判；
// vitro 旧零诊断静默误收（static/register/auto 三者同病——限定符循环吞入
// pending 后成员循环无收割点）。修后双侧编译失败判 match。
// 对照组：局部 auto int（gap keyword_compat.c 登记的宽容面，保持接受）。
#include <stdio.h>
struct Edge { static int src; };         /* 非法：成员 static */
union U { register int u1; };            /* 非法：成员 register */
struct T { auto int t1; };               /* 非法：成员 auto */
int main(void) {
  auto int y = 10;                       /* 合法：局部 auto（宽容面对照组） */
  struct Edge e;
  e.src = y;
  printf("%d\n", e.src);
  return 0;
}
