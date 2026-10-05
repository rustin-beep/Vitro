/* 条目 4 回归（负向）：普通字符指令不匹配时，按 C11 7.21.6.2 **停止解析**、
 * 目标变量保持原值、返回已成功赋值的项数（0）。 */
#include <stdio.h>

int main() {
    int x = -1;
    int r = scanf("a=%d", &x);
    printf("x=%d r=%d\n", x, r);
    return 0;
}
