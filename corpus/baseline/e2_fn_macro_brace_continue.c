// @category: baseline
// #432 A4：continue 同族——{…} 宏体内 continue 绑定外层循环（四编译器
// 一致 exit=3,c=2；i==2 时 continue 跳过 c 自增）。修复前被劫持（c=3）。
#include <stdio.h>
#define SKIP(x) {if(x) continue;}
int main() {
  int i = 0, c = 0;
  while (i < 3) { i = i + 1; SKIP(i == 2); c = c + 1; }
  printf("exit=%d,%d\n", i, c);
  return 0;
}
