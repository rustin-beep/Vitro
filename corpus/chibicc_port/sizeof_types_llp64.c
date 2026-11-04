// @category: chibicc_port
// source: chibicc test/sizeof.c / decl.c（MIT, © 2019 Rui Ueyama）
// topic: 基本类型 sizeof（Win LLP64 口径：long=4/long long=8；指针尺寸与 short=2 属 Vitro 差异面，见 deferred）
#include <stdio.h>
int main(void) {
  printf("%d\n", (int)sizeof(char));
  printf("%d\n", (int)sizeof(int));
  printf("%d\n", (int)sizeof(long));            // Win=4
  printf("%d\n", (int)sizeof(long long));       // 8
  printf("%d\n", (int)sizeof(unsigned long));
  printf("%d\n", (int)sizeof(unsigned long long));
  printf("%d\n", (int)sizeof(float));
  printf("%d\n", (int)sizeof(double));
  printf("%d\n", (int)sizeof(int[4]));
  printf("%d\n", (int)sizeof(int[3][4]));
  printf("%d\n", (int)sizeof(struct {int a; int b;}));
  printf("%d\n", (int)sizeof(-10 + (long)5));   // long 4B → 4
  printf("%d\n", (int)sizeof((long)-10 + 5));   // 4
  printf("%d\n", (int)sizeof((char)1 + (char)1));  // 提升 int=4
  printf("%d\n", (int)sizeof((short)1 + (short)1)); // 提升 int=4
  printf("%d\n", (int)sizeof(1?2:3));
  printf("%d\n", (int)sizeof(1?(short)2:(char)3));  // 提升 int=4
  printf("%d\n", (int)sizeof(1.0f+2));          // 4
  printf("%d\n", (int)sizeof(1.0+2));           // 8
  printf("%d\n", (int)sizeof(1.0f*2));
  printf("%d\n", (int)sizeof(1.0*2));
  char ci; printf("%d %d\n", (int)sizeof(++ci), (int)sizeof(ci++));  // sizeof 不求值
  // 注：chibicc 原 _Bool 面（_Bool x=2 → 1、(_Bool)2 → 1）——Vitro 不归一化（保持 2；初始化与 cast 两路，
  // clang 0 1 1 / 1 1 vs Vitro 0 1 2 / 1 2；(_Bool)(char)256 同族）——_Bool 归一化缺失 DIFF 候选，移 deferred
  return 0;
}
