// @category: baseline
// E1：无后缀浮点字面量为 double（C 标准；此前建模为 float，
// 2.2e-308 经 f32 位模式存储下溢为 0）
#include <stdio.h>
int main() {
    double d = 0.1;
    float f = 0.1f;
    printf("%d %d\n", d == 0.1, (double)f == 0.1);
    printf("%.3g\n", 2.2e-308 * 1e0);
    double sub = 2.2250738585072014e-308;
    printf("%.3g\n", sub);
    float g = 1.5f;
    printf("%.2f %.2f\n", g, 2.5);
    return 0;
}
