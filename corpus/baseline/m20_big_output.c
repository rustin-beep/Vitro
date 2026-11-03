// @category: baseline
// 绿锚（#437 即可入库批）：审阅 v2 M20 b1「305KB 大输出」无发现面——12000 行 ULL 滚雪球哈希序列
// 全量逐位一致（流式输出稳定性压测）。来源：tmp/review_v2_M20/probes/b1_big.c
#include <stdio.h>
int main(void){
  unsigned long long h = 1469598103934665603ULL;
  for (int i = 0; i < 12000; i++) {
    printf("%d,%llu\n", i, h);
    h = h * 1099511628211ULL + i;
  }
  printf("END %llu\n", h);
  return 0;
}
