// @category: chibicc_port
// source: chibicc test/arith.c（MIT, © 2019 Rui Ueyama）— ASSERT 形态 port 为 printf 基线
// topic: 整数四则/一元正负/比较运算边界
#include <stdio.h>
int main(void) {
  printf("%d %d %d %d\n", 0, 42, 5+20-4, 12 + 34 - 5);
  printf("%d %d %d\n", 5+6*7, 5*(9-6), (3+5)/2);
  printf("%d %d %d\n", -10+20, - -10, - - +10);
  printf("%d %d %d %d\n", 0==1, 42==42, 0!=1, 42!=42);
  printf("%d %d %d %d %d %d\n", 0<1, 1<1, 2<1, 0<=1, 1<=1, 2<=1);
  printf("%d %d %d %d %d %d\n", 1>0, 1>1, 1>2, 1>=0, 1>=1, 1>=2);
  // 注：chibicc 原 ASSERT(0, 1073741824*100/100)（int 溢出回绕）在 Vitro 触发教学护栏 trap——已知差异（D10 族），移 deferred
  return 0;
}
