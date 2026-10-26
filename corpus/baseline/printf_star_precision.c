/* printf_star_precision.c —— #159 审阅 P2-2 第二锚：星号精度槽多形态
 *
 * 与 printf_star_member.c 互补：负精度（* 为负 ⇒ 精度被忽略）、双星号
 * （宽度+精度双槽连续吃成员）、星号槽与值槽混排——覆盖 resolve 回写
 * 在星号槽族的多分支（#161 尾参同族面）。
 */
#include <stdio.h>

struct Cfg { int width; int prec; };
struct Cfg cfg = { 8, 3 };

int main(void) {
    /* 双星号：宽度槽 + 精度槽都吃 struct 成员 */
    printf("[%*.*f]\n", cfg.width, cfg.prec, 3.14159);
    /* 负星号宽度：左对齐语义（-width）——星号槽经成员取负 */
    printf("[%-*d]\n", -cfg.width, 42);
    /* 星号精度 + 值槽成员混排（两槽都从 struct 取，验证槽位不串） */
    printf("[%.*d|%d]\n", cfg.prec, 9, cfg.width);
    return 0;
}
