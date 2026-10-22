/*
 * @category: float_literal
 * 无小数位浮点常量（#247 修复锚，2026-10-22）：C99 §6.4.4.4 允许
 * digit-sequence '.' 小数部分缺省（10. / 10.e5）——旧扫描器把 `10.`
 * 拆成「数字 + .」两 token，解析器按成员访问报「预期成员名称」/
 * E3041 误拒。点后三态（数字/f/F、e 指数、常量终结符）全形态对照。
 * clang 真值对拍。
 */
#include <stdio.h>

int main(void) {
    double a = 10.;
    double b = 10.e5;
    double c = 2.f;
    double d = .5;
    double e = 10.0;
    double f = 1e5;
    double g = 3.5e-2;
    double h = 7.e2;
    printf("%f %f %f %f\n", a, b, c, d);
    printf("%f %f %f %f\n", e, f, g, h);
    double sum = a + b + h;
    printf("sum=%.1f\n", sum);
    return 0;
}
