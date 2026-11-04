// @category: chibicc_port
// source: chibicc test/union.c（MIT, © 2019 Rui Ueyama）— statement expression 拆变量
// topic: union 成员重解释（int↔char[4] 字节序）、union 赋值、匿名 struct 成员
#include <stdio.h>
int main(void) {
  union { int a; char b[4]; } u;
  u.a = 515;                       // 0x0203
  printf("%d %d %d %d\n", u.b[0], u.b[1], u.b[2], u.b[3]);  // 3 2 0 0（小端）
  union { int a,b; } u2, u3; u2.a=3; u3.a=5; u3=u2; printf("%d\n", u3.a);
  union { struct { int a,b; } c; } u4, u5; u4.c.b=3; u5.c.b=5; u5=u4; printf("%d\n", u5.c.b);
  // 注：chibicc 原匿名 struct×long 重解释（ue.e=0xdeadbeef → ef be ad de）——Vitro 输出 ef ef ef ef
  //（union 长成员写短成员数组按低位字节广播，M03「typedef union 炸穿」同族 DIFF 候选），移 deferred
  struct { union { int a,b; }; union { int c,d; }; } su;     // 匿名 union 成员
  su.a=3; printf("%d\n", su.b);
  su.d=5; printf("%d\n", su.c);
  return 0;
}
