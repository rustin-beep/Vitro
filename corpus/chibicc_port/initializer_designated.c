// @category: chibicc_port
// source: chibicc test/initializer.c（MIT, © 2019 Rui Ueyama）— statement expression 拆变量
// topic: 指定初始化器（struct .成员= 面与嵌套覆盖形态）
// 注：chibicc 原文件数组 designated 面（{1,2,3,[0]=4,5} 平铺+指定混排、[1].b=1,2,[0]=3,4 等）
//     Vitro E2005 拒收（M11 族缺陷面），移 deferred；本文件只保 struct/union .成员 面
#include <stdio.h>
int main(void) {
  struct { int a,b; } s = {1,2,.b=3,.a=4};
  printf("%d %d\n", s.a, s.b);                  // 4 3
  // 注：chibicc 原 {.c=1,2}（designated 位置后子聚合平铺）——Vitro E3006 拒收（gap 候选），移 deferred
  // 注：chibicc 原 {.c.b=1}（成员链 designated 嵌套）——Vitro E2005 拒收（gap 候选），移 deferred
  // 注：chibicc 原 {.a=1,2} 与 {.a[1]=1}（数组成员 designated/下标 designated）Vitro E2005 拒收，移 deferred
  // 注：chibicc 原 union {.b[0]=0xff}/{.b[1]=0xff}（union 数组成员 designated）Vitro E2005 拒收，移 deferred
  return 0;
}
