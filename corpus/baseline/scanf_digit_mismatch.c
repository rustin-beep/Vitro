/* 病 13（#61，2026-10-10）：scanf %d/%u 无数字误计数——旧臂 token 空也写 0 且
 * matched++（对 UCRT/glibc 双分叉，C11 §7.21.6.2 匹配失败应返 0 不写）；修为
 * 对齐病 9 i/x/o 臂的失败语义（游标回退、不计 matched、终止）。%f 实测无恙
 * （token 空 break 已对，台账原口径含 %f 系登记时推测——本批更正）。stdin 版
 * 跨调用锚定「回退」可观测面：首转换失败后字符退回输入流，%c 仍可读到。 */
#include <stdio.h>

int main() {
    int d = -99;
    int u = -99;
    char c = '?';
    int r1 = sscanf("abc", "%d", &d);
    int r2 = sscanf("x9", "%u", &u);
    printf("r1=%d d=%d r2=%d u=%d\n", r1, d, r2, u);
    int r3 = scanf("%d", &d);
    int r4 = scanf("%c", &c);
    printf("r3=%d d=%d r4=%d c=%c\n", r3, d, r4, c);
    return 0;
}
