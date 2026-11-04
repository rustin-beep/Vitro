// @category: chibicc_port
// source: chibicc test/control.c（MIT, © 2019 Rui Ueyama）— statement expression 拆变量
// topic: if/else、for 累加、while、空语句块、逗号表达式
#include <stdio.h>
int main(void) {
  int x;
  if (0) x=2; else x=3; printf("%d\n", x);
  if (1-1) x=2; else x=3; printf("%d\n", x);
  if (1) x=2; else x=3; printf("%d\n", x);
  int i=0, j=0; for (i=0; i<=10; i=i+1) j=i+j; printf("%d\n", j);
  i=0; while(i<10) i=i+1; printf("%d\n", i);
  printf("%d\n", (1,2,3));           // 逗号表达式取末值
  j=0; for (int k=0; k<=10; k=k+1) j=j+k; printf("%d\n", j);
  int inner=3; j=0; for (int k=0; k<=10; k=k+1) j=j+k;
  printf("%d %d\n", inner, j);       // for 声明作用域遮蔽
  return 0;
}
