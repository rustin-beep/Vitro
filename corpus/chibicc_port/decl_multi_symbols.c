#include <stdio.h>

// @category: chibicc port——多符号声明符链（decl.c 主题）：一条声明多声明符
// 混合「带初始化器 / 仅声明」两形态 × 全局/局部两域 × static 存储类（#433 ②
// extra 变量同轨修复后的行为面）。clang 真值：1 2 3 4 5 / 10 20 30。

int a = 1, b = 2, c;
static int d = 4, e;

int main() {
    int x = 10, y, z = 30;
    y = 20;
    c = 3;
    e = 5;
    printf("%d %d %d %d %d\n", a, b, c, d, e);
    printf("%d %d %d\n", x, y, z);
    return 0;
}
