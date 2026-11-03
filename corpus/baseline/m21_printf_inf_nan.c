// @category: baseline
// 绿锚（#437 即可入库批）：审阅 v2 M21/M20 ±inf 全形态好面（速查表 G13 行）——inf/-INF 宽度精度组合
// 三方一致；NaN 大小写族（G8-G10）属分叉面不入本文件。来源：tmp/review_v2_M21/probes/p05_g_edge.c 注 inf 段
#include <stdio.h>
int main(void) {
    double inf = 1.0 / 0.0 * 1.0;
    printf("%f\n", inf);
    printf("%f\n", -inf);
    printf("%e\n", inf);
    printf("%g\n", inf);
    printf("%.3f\n", inf);
    printf("[%10f]\n", inf);
    printf("[%-10f|]\n", -inf);
    return 0;
}
