/*
 * @category: param_declarator
 * 无名抽象数组声明符形参（#252 修复锚，2026-10-22）：C11 §6.7.6.3p13
 * 原型里参数名可省——`void f(int[], int)` 旧解析器对「类型后直接 [」
 * 报「预期标识符名称」E2005 误拒（具名 `int xs[]` 一直支持，缺口在
 * 无名+抽象数组组合）。原型/带尺寸/二维/调用定义全链对照。clang 对拍。
 */
#include <stdio.h>

void f(int[], int);
void take(char[]);
void sized(int[3]);
void matrix(int[][4], int);

static int total(int xs[], int n) {
    int s = 0;
    for (int i = 0; i < n; i++) s += xs[i];
    return s;
}

int main(void) {
    int a[3] = { 1, 2, 3 };
    f(a, 3);
    char msg[4] = "ok";
    take(msg);
    sized(a);
    int grid[2][4] = { { 1, 2, 3, 4 }, { 5, 6, 7, 8 } };
    matrix(grid, 2);
    printf("total=%d\n", total(a, 3));
    return 0;
}

void f(int xs[], int n) { printf("f=%d\n", total(xs, n)); }
void take(char s[]) { printf("take=%s\n", s); }
void sized(int v[]) { printf("sized=%d\n", v[0] + v[2]); }
void matrix(int m[][4], int rows) {
    int s = 0;
    for (int i = 0; i < rows; i++)
        for (int j = 0; j < 4; j++) s += m[i][j];
    printf("matrix=%d\n", s);
}
