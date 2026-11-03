// @category: chibicc_port
// source: chibicc test/typedef.c / enum.c（MIT, © 2019 Rui Ueyama）
// topic: typedef 作用域与遮蔽/枚举常量值/枚举 sizeof
#include <stdio.h>
typedef int MyInt;
int main(void) {
  typedef int t; t x = 1; printf("%d\n", x);
  typedef struct { int a; } ts; ts sx; sx.a = 1; printf("%d\n", sx.a);
  typedef int t2; t2 t2v = 1; printf("%d\n", t2v);
  { typedef int inner; inner iv = 9; printf("%d\n", iv); }   // 块内 typedef
  MyInt mi = 3; printf("%d\n", mi);
  // 注：chibicc 原 typedef int MyInt2[4]（一行多声明含数组 typedef）——Vitro E2005 拒收（gap 候选），移 deferred
  enum { zero, one, two };
  printf("%d %d %d\n", zero, one, two);
  enum { five=5, six, seven };
  printf("%d %d\n", five, six);
  enum { z2, five2=5, three=3, four };
  printf("%d %d %d %d\n", z2, five2, three, four);           // 0 5 3 4
  enum { e0, e1, e2 } ev; printf("%d\n", (int)sizeof(ev));    // 4
  enum te { te0, te1 } tev; printf("%d\n", (int)sizeof(tev)); // 4
  return 0;
}
