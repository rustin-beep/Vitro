/* 条目 3 回归：scanf 返回"成功匹配并赋值的项数"（C11 7.21.6.2）。
 * 修复前 scanf 被视作 void：`int r = scanf(...)` 报 E3004，
 * `while (scanf(...) != EOF)` 一类写法完全不可用。 */
#include <stdio.h>

int main() {
    int a = 0, b = 0;
    int r = scanf("%d %d", &a, &b);
    printf("%d %d %d\n", a, b, r);
    return 0;
}
