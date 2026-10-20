// @category: baseline
// #177 写侧红锚：char 全局 StoreGlobal 恒 4 字节越权写抹相邻变量。
// x/y 逐字节紧排，x 赋值不得破坏 y（vitro 曾把 1025..1027 清零）。
#include <stdio.h>
char x, y;
int main(void) {
  x = '0';
  y = 127;
  x = 48;
  printf("%d %d\n", x, y);
  return 0;
}
