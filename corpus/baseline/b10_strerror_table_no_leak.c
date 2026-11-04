/* B10 #434 / M22 A-7：strerror 返回静态串语义——遵守 C 语义（不 free）
 * 不应有泄漏报告；文案表 = UCRT 口径（病 47 + B10 补 34）。循环取表内
 * 全值（表外 errnum 的文案覆盖面另属扩表批，不入本例防对拍分叉）。 */
#include <stdio.h>
#include <string.h>
int main(){
  int errs[] = {0, 1, 2, 13, 22, 33, 34, 99};
  for (int i = 0; i < 8; i++) printf("%d=%s\n", errs[i], strerror(errs[i]));
  return 0;
}
