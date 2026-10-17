// @category: baseline
// #138 合法形态锚（2026-10-17）：参数作用域 = 函数体（C11 §6.2.1p4）
// 修复后，内层 block shadowing / for-init 声明 / 全局遮蔽必须照旧合法
// ——clang redefinition 口径只覆盖函数体最外层声明与参数同名。
#include <stdio.h>
int g = 100;
void check(int p) {
    printf("param=%d\n", p);
    {
        int p = 300;
        printf("block shadow=%d\n", p);
    }
    printf("after block=%d\n", p);
    for (int p = 0; p < 2; p++) {
        printf("for p=%d\n", p);
    }
}
int main(void) {
    check(1);
    int g = 10;
    printf("main local g=%d\n", g);
    return 0;
}
