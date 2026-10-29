/* issue #213（2026-10-28）：语法错不遮蔽语义错——多重错误混合样本
 *（《学生错误用例集》§8.1 原文）。旧形态：语法错早退只报 2 条 E2005，
 * 语义面（c 未声明 / scanf 实参类型）零报告；修后语法 E2005×2 +
 * E3023（c 未声明）+ W3063（scanf %d 与 int 不匹配）同帧报出。
 * 双侧编译失败判 match：clang 对缺分号同样编译期拒（-fsyntax-only
 * 语义同向）。 */
#include <stdio.h>
int main() {
    int a = 10
    int b;
    b = a + c;
    scanf("%d", a);
    for (int i = 0; i < 5; i++)
        printf("%d ", i)
    return 0;
}
