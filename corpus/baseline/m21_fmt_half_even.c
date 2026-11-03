// @category: baseline
// 绿锚（#437 即可入库批）：审阅 v2 M21 p04 格式化好面（速查表 G13 行）——half-even 四组、%.20f 0.1、
// ±0.0 形态三方一致（bigint 精确十进制路径）。探针源 p04 中 0.005 行属未证明面，预检分拣后取舍。
// 来源：tmp/review_v2_M21/probes/p04_half_even.c
#include <stdio.h>
int main(void) {
    printf("%.2f\n", 0.125);          // half-even: 0.12
    printf("%.2f\n", 0.375);          // half-even: 0.38
    printf("%.0f\n", 2.5);            // half-even: 2
    printf("%.0f\n", 3.5);            // half-even: 4
    printf("%.0f\n", -2.5);           // half-even: -2
    printf("%.0f\n", -0.0);           // -0
    printf("%.2f\n", -0.0);           // -0.00
    printf("%.17g\n", 0.1);
    printf("%.20g\n", 0.1);
    printf("%.15e\n", 0.1);
    return 0;
}
