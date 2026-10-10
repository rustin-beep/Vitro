/* #59 题 1（裁定 2026-10-10：glibc 2.43 实测反转矩阵）：%i/%x 的 "0x"
 * 残缺前缀 = 匹配失败——不写变量、不计数；且 "0x" 两字符被消费不退回
 *（UCRT/glibc 双派 stdin 实测一致：%c 随后读到 'Z'）。返回值面不入本例
 *（UCRT -1 EOF 派 vs C11 已配数 0 派——分叉见 corpus/gap/scanf_0x_retval.c
 * 与 known_direct）。正常前缀（0x1f）匹配保留。strtol 面不入对拍（endptr
 * 消费量三方分叉：UCRT 0 / glibc 1 / C11 读法 1——单独口径注记）。 */
#include <stdio.h>

int main() {
    int a = -99;
    int b = -99;
    int c = -99;
    sscanf("0x", "%i", &a);
    sscanf("0x", "%x", &b);
    sscanf("0x1f", "%i", &c);
    printf("a=%d b=%d c=%d\n", a, b, c);
    int d = -99;
    char e = '?';
    scanf("%i", &d);
    scanf("%c", &e);
    printf("d=%d e=%c\n", d, e);
    return 0;
}
