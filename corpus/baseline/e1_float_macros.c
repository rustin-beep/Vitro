// @category: baseline
// E1 B 档：float.h（科学计数法字面量 + double 宏）
#include <stdio.h>
#include <float.h>
int main() {
    printf("%.3g %.3g\n", DBL_EPSILON, DBL_MIN);
    printf("%.3g\n", DBL_MAX);
    printf("%.3g %.3g\n", FLT_MAX, FLT_MIN);
    printf("%d %d\n", FLT_DIG, DBL_DIG);
    double e = 1e-3;
    printf("%.3g\n", e * 1e2);
    return 0;
}
