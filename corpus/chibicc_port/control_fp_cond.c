// @category: chibicc_port
// source: chibicc test/control.c（MIT, © 2019 Rui Ueyama）— statement expression 拆变量
// topic: 浮点数作控制条件（if/for/while/do 直接判零面——非 &&/|| 操作数臂）
#include <stdio.h>
int main(void) {
  int x;
  if (0.0) x=3; else x=5; printf("%d\n", x);
  if (0.1) x=3; else x=5; printf("%d\n", x);
  x=5; if (0.0) x=3; printf("%d\n", x);
  x=5; if (0.1) x=3; printf("%d\n", x);
  double i=10.0; int j=0; for (; i; i--, j++); printf("%d\n", j);
  i=10.0; j=0; do j++; while(--i); printf("%d\n", j);
  printf("%d\n", 0.0 ? 3 : 5);
  printf("%d\n", 1.2 ? 3 : 5);
  return 0;
}
