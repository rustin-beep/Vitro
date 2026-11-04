// @category: chibicc_port
// source: chibicc test/float.c（MIT, © 2019 Rui Ueyama）
// topic: 整型↔浮点全转换矩阵（值域内小值面；LL↔float 边界域见 deferred C1/C11）
#include <stdio.h>
int main(void) {
  printf("%d %d %d %d\n",
    (int)(float)(char)35, (int)(float)(short)35, (int)(float)(int)35, (int)(float)(long)35);
  printf("%d %d %d %d\n",
    (int)(float)(unsigned char)35, (int)(float)(unsigned short)35,
    (int)(float)(unsigned int)35, (int)(float)(unsigned long)35);
  printf("%d %d %d %d\n",
    (int)(double)(char)35, (int)(double)(short)35, (int)(double)(int)35, (int)(double)(long)35);
  printf("%d %d\n", (char)(float)35, (short)(float)35);
  printf("%d %d\n", (int)(float)35, (unsigned char)(float)35);
  printf("%d %d\n", (unsigned short)(float)35, (unsigned int)(float)35);
  printf("%d\n", (char)(double)35);
  printf("%d %d\n", (short)(double)35, (int)(double)35);
  printf("%d\n", (unsigned char)(double)35);
  printf("%d %d\n", (unsigned short)(double)35, (unsigned int)(double)35);
  // 注：chibicc 原 ASSERT(-2147483648, (double)(unsigned long)(long)-1)——UB 哨兵三方各异（Win 4294967295 / WSL gcc -9223372036854775808 / WSL clang 垃圾值），不 port
  return 0;
}
