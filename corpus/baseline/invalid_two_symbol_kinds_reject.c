// @category: baseline
// #182 D-2 红锚补面：函数名与文件作用域变量同名（不同类符号重定义，
// C11 6.2.7p1）——static×static / 普通×普通两变体；对照组不同名合法。
#include <stdio.h>
static int g = 3;
static int g(int x) { return x; }      /* 非法：与变量同名 */
int h = 4;
int h2(int x) { return x; }            /* 对照：不同名合法 */
int main(void) {
  printf("%d\n", 1);
  return 0;
}
