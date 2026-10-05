/* 条目 4 回归（正向）：格式串中的普通字符指令 `a=` 必须与输入精确匹配。
 * 修复前字面字符被整段忽略，`scanf("a=%d", &x)` 读 `a=42` 得到 x=0。 */
#include <stdio.h>

int main() {
    int x = 0;
    int r = scanf("a=%d", &x);
    printf("x=%d r=%d\n", x, r);
    return 0;
}
