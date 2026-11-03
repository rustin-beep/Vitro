// @category: chibicc_port
// source: chibicc test/arith.c（MIT, © 2019 Rui Ueyama）— ASSERT 形态 port；statement expression 拆变量
// topic: 指针差值/指针比较/指针±整数表达值（值面，非 sizeof 面）
#include <stdio.h>
int main(void) {
  int x; int *p = &x;
  printf("%d\n", (int)(p+20-p));
  printf("%d\n", p+20-p > 0);
  printf("%d\n", (int)(p-20-p));
  printf("%d\n", p-20-p < 0);
  printf("%d\n", 3&1);
  return 0;
}
