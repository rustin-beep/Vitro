/* 下游需求 A1 回归（EOF 之后的后续读）：流耗尽返回 EOF 必须**可重复**，
 * 且耗尽之后再喂入的内容不应"复活"（EOF 粘滞，对齐 C11 7.21.6.2 与
 * Clang/glibc 的 FILE 状态语义）。
 *
 * 修复前：首次 EOF 语境会进入 waiting_input 挂死。
 */
#include <stdio.h>

int main() {
    int a = 0;
    int b = 0;
    int r1 = scanf("%d", &a);
    int r2 = scanf("%d", &b);
    int c = getchar();
    printf("r1=%d r2=%d c=%d\n", r1, r2, c);
    return 0;
}
