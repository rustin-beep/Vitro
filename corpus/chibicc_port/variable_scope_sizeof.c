// @category: chibicc_port
// source: chibicc test/variable.c（MIT, © 2019 Rui Ueyama）— statement expression 拆变量
// topic: 局部/全局变量、数组下标赋值、作用域遮蔽、sizeof 表达式副作用（不含指针/short/long 尺寸面——见 deferred）
#include <stdio.h>
int g1, g2[4];
static int g3 = 3;
int main(void) {
  int a; a=3; printf("%d\n", a);
  int z=5; printf("%d %d\n", a+z, 8);
  int b; b=3; int c; a=b=c=3; printf("%d %d\n", a+b, a);
  int foo123=3; int bar=5; printf("%d\n", foo123+bar);
  int x; printf("%d %d\n", (int)sizeof(x), (int)sizeof x);
  int arr[4]; printf("%d\n", (int)sizeof(arr));
  // 注：chibicc 原 sizeof(*x)/sizeof(**x)（对数组表达式解引用取元素尺寸）——Vitro E3021 拒收（gap 候选），移 deferred
  int s=1; printf("%d %d\n", (int)sizeof(s=2), s);  // sizeof 不求值
  printf("%d\n", g1);
  g1=3; printf("%d\n", g1);
  g2[0]=0; g2[1]=1; g2[2]=2; g2[3]=3;
  printf("%d %d %d %d\n", g2[0], g2[1], g2[2], g2[3]);
  printf("%d %d\n", (int)sizeof(g1), (int)sizeof(g2));
  char c1=1; char c2=2; printf("%d %d\n", c1, c2);
  char ca[10]; printf("%d\n", (int)sizeof(ca));
  int sh=2; { int sh=3; } printf("%d\n", sh);   // 块遮蔽
  int outer=2; { outer=3; } printf("%d\n", outer);
  printf("%d\n", g3);
  return 0;
}
