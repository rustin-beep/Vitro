// @category: baseline
// #432 A4 / M01 d3：函数式宏体 {…} 不自动包装 do{…}while(0)——宏体内
// break 绑定外层循环（四编译器编译运行一致 exit=1；i==1 时 break 跳出
// while）。修复前引擎自包 do-while(0) 把 break 劫持到包装层（exit=3），
// 零诊断行为反转。
#include <stdio.h>
#define CHK(x) {if(x) break;}
int main() {
  int i = 0;
  while (i < 3) { i = i + 1; CHK(i == 1); }
  printf("exit=%d\n", i);
  return 0;
}
