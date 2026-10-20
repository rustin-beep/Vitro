// @category: baseline
// #177 写侧实战形态（#161 排查中挖出）：char 全局紧邻字面量池串，
// 赋值的 4 字节写窗抹掉 "%c" 使 sscanf 读到空格式串 0 转换。
#include <stdio.h>
char x, y;
int main(void) {
  x = '0';
  y = '0';
  int n = sscanf("P", "%c", &x);
  printf("n=%d x=%c\n", n, x);
  return 0;
}
