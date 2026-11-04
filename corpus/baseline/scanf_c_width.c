/* #428 B5 批（2026-11-04）：scanf %Nc 字段宽度端到端锚——C11 §7.21.6.2
 * 宽度适用所有转换（#71 病 23 修漏 %c 臂）。clang/UCRT + glibc 双派真值：
 * %3c 写 3 字节不写 NUL、next='d'；%*2c 抑制臂同吃宽度；%1c 单字节。
 * 修前形态：vitro 只读 1 字节（scanf+sscanf 双臂同漏）。 */
#include <stdio.h>

int main() {
    char buf[8] = {0};
    int r = scanf("%3c", buf);
    printf("r=%d buf=[%c%c%c] b3=%d\n", r, buf[0], buf[1], buf[2], buf[3]);
    int c = getchar();
    printf("next=%d\n", c);
    int x = -1;
    r = scanf("%*2c%d", &x);
    printf("r=%d x=%d\n", r, x);
    char b2[4] = {'Q', 'Q', 'Q', 'Q'};
    r = scanf("%1c", b2);
    printf("r=%d b2=[%c%c]\n", r, b2[0], b2[1]);
    /* sscanf 壳同款（双臂同漏防单侧修） */
    char b3[8] = {0};
    r = sscanf("abcdef", "%3c", b3);
    printf("ss r=%d b3=[%c%c%c]\n", r, b3[0], b3[1], b3[2]);
    char b4[4] = {'Q', 'Q', 'Q', 'Q'};
    r = sscanf("xyz", "%*2c%1c", b4);
    printf("ss r=%d b4=[%c%c]\n", r, b4[0], b4[1]);
    return 0;
}
