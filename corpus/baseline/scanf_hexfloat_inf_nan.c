/* #428 B5 批（2026-11-04）：scanf 浮点族端到端锚——hexfloat 输入（病 24
 * 半修收口：token 收对、解析层丢 → 0.0）+ 缺臂 e/E/g/G/a/A/F（C11
 * §7.21.6.2 p12 浮点族输入语义全同 strtod）+ inf/nan token 形态。
 * clang/UCRT + glibc 双派真值。NaN 值打印不入本例（printf %f NaN 拼法
 * 属 B4 批 #427 在途修复面，避免跨批撞面——nan 只验 r 计数与 inf 面）。 */
#include <stdio.h>

int main() {
    double d = -1, e = -1, g = -1, h = -1;
    float f = -1;
    int r = scanf("%lf %le %lg %la", &d, &e, &g, &h);
    printf("r=%d d=%.2f e=%.2f g=%.2f h=%.2f\n", r, d, e, g, h);
    r = scanf("%f", &f);
    printf("r=%d f=%.2f\n", r, (double)f);
    double i1 = -1, i2 = -1;
    r = scanf("%lf %le", &i1, &i2);
    printf("r=%d inf=%.1f INF=%.1f\n", r, i1, i2);
    double n1 = 0;
    r = scanf("%le", &n1);
    printf("r=%d\n", r);
    /* sscanf 壳缺臂 + %X ≡ %x（修前 e/a/X 落 else 兜底不消费不计数） */
    double s1 = -1;
    r = sscanf("2.5 25.5 .5 0x10p1 1e2", "%le %lF %lg %la %lE", &s1, &e, &g, &h, &d);
    printf("ss r=%d %.2f %.2f %.2f %.2f %.2f\n", r, s1, e, g, h, d);
    unsigned ux = 7;
    unsigned long long ulx = 7;
    r = sscanf("ff FF", "%X %llX", &ux, &ulx);
    printf("ss r=%d ux=%u ulx=%llu\n", r, ux, ulx);
    return 0;
}
