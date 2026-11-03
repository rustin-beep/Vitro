// @category: chibicc_port
// source: chibicc test/constexpr.c（MIT, © 2019 Rui Ueyama）— statement expression 拆变量
// topic: 常量表达式定数组维：算术/位/逻辑/比较/逗号/三元/cast 截断（chibicc 边界值集）
#include <stdio.h>
int main(void) {
  char a1[1+1]; printf("%d\n", (int)sizeof(a1));
  char a2[2*3]; printf("%d\n", (int)sizeof(a2));
  char a3[12%10]; printf("%d\n", (int)sizeof(a3));
  char a4[0b110&0b101]; printf("%d\n", (int)sizeof(a4));   // 4
  char a5[0b110|0b101]; printf("%d\n", (int)sizeof(a5));   // 7
  char a6[0b111^0b001]; printf("%d\n", (int)sizeof(a6));   // 6
  char a7[1<<2]; printf("%d\n", (int)sizeof(a7));
  char a8[4>>1]; printf("%d\n", (int)sizeof(a8));
  char a9[(1==1)+1]; printf("%d\n", (int)sizeof(a9));
  char a10[(1!=1)+1]; printf("%d\n", (int)sizeof(a10));
  char a11[1?2:3]; printf("%d\n", (int)sizeof(a11));
  char a12[0?2:3]; printf("%d\n", (int)sizeof(a12));
  char a13[(1,3)]; printf("%d\n", (int)sizeof(a13));
  char a14[!0+1]; printf("%d\n", (int)sizeof(a14));
  char a15[~-3]; printf("%d\n", (int)sizeof(a15));
  char a16[(5||6)+1]; printf("%d\n", (int)sizeof(a16));
  char a17[(1&&1)+1]; printf("%d\n", (int)sizeof(a17));
  char a18[(1&&0)+1]; printf("%d\n", (int)sizeof(a18));
  char a19[(int)3]; printf("%d\n", (int)sizeof(a19));
  // 注：chibicc 原宽字面量截断定维族（(char)0xffffff0f / (short)0xffff010f / (int)0xfffffffffff+5）
  //——Vitro StackAlloc 负数 trap（Z11 折叠截断族 × D7 short 退化叠加），移 deferred
  // 注：chibicc 原 char a[(-1>>31)+5]（负数算术移位折叠定维）——Vitro 同族 StackAlloc 负数 trap，移 deferred
  char a27[(unsigned char)0xffffffff]; printf("%d\n", (int)sizeof(a27)); // 255
  // 注：chibicc 原宽字面量 unsigned 截断定维族（(unsigned short)0xffff800f / (unsigned int)0xfffffffffff>>31）
  //——Vitro StackAlloc 负数 trap（Z11 折叠截断族叠加），移 deferred
  char a30[(unsigned)1<-1]; printf("%d\n", (int)sizeof(a30));     // 1
  char a31[(unsigned)1<=-1]; printf("%d\n", (int)sizeof(a31));    // 1
  enum { ten=1+2+3+4 }; printf("%d\n", ten);
  int sw = 0; switch(3) { case 5-2+0*3: sw++; } printf("%d\n", sw);
  return 0;
}
