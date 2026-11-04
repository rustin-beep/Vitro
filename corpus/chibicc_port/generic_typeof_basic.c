// @category: chibicc_port
// source: chibicc test/generic.c / typeof.c（MIT, © 2019 Rui Ueyama）— statement expression 拆变量
// topic: _Generic 类型选择（double/int/float）与 typeof 声明（Vitro 支持面——预检分拣）
#include <stdio.h>
int main(void) {
  printf("%d\n", _Generic(100.0, double: 1, int *: 2, int: 3, float: 4));
  printf("%d\n", _Generic((int *)0, double: 1, int *: 2, int: 3, float: 4));
  printf("%d\n", _Generic(100, double: 1, int *: 2, int: 3, float: 4));
  printf("%d\n", _Generic(100.0f, double: 1, int *: 2, int: 3, float: 4));
  // 注：chibicc 原 typeof(int)（类型参数形态）——Vitro E2003 拒收（仅支持 typeof(表达式)，单测 probe_typeof_int/expr 复核），移 deferred
  int ix; typeof(ix) iy; printf("%d\n", (int)sizeof(iy));
  return 0;
}
