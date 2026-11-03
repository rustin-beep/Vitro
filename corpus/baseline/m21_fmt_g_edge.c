// @category: baseline
// 绿锚（#437 即可入库批）：审阅 v2 M21 p05 %g 边界好面（速查表 G11/G12 行）——%g 默认精度段三方一致；
// %.17g 高精度段分叉形态（G1-G7 族）不入本文件（修复后入库批覆盖）。
// 来源：tmp/review_v2_M21/probes/p05_g_edge.c
#include <stdio.h>
int main(void) {
    printf("%g\n", 1e23);           // 1e+23（默认精度一致——G11）
    printf("%g\n", 999999.99);
    printf("%g\n", 0.0001);
    printf("%g\n", 0.00001);
    printf("%g\n", 123456.0);
    printf("%g\n", 1234567.0);
    printf("%.3e\n", 9.99999e99);
    printf("%.0e\n", 0.0);
    printf("%.0g\n", 0.0);
    printf("%.0g\n", 123.0);
    printf("%g\n", -0.0);
    printf("%e\n", 1e100);
    printf("%e\n", 1e-100);
    printf("%.2e\n", 9.99e-5);
    printf("%g\n", 1.7976931348623157e308);   // DBL_MAX（G12 族）
    return 0;
}
