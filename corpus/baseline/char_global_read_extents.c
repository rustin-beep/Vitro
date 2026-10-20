// @category: baseline
// #177 读侧红锚：char 全局 LoadGlobal 32 位读卷入右侧邻居字节。
// s（signed，存 200 窄化为 -56）与 b 紧排时 32 位读得 0x000042C8 类
// 垃圾；unsigned char 读应零扩展、signed 读应符号扩展。
#include <stdio.h>
char s;
char a, b;
unsigned char u;
int main(void) {
  s = 200;
  a = 'A';
  b = 'B';
  u = 200;
  printf("%d %d %d %d\n", s, u, a == 'A', b);
  return 0;
}
