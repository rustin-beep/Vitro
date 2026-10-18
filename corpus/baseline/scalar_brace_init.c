/*
 * @category: const_fold
 * 标量初始化器的大括号包裹（#183 修复锚，2026-10-18 深挖批）：
 * C11 6.7.9p11「可选大括号包裹的表达式」——int x = {5} ≡ 5；
 * 多余元素对齐 clang -Wexcess（W3005 + 取首）。九形态矩阵：
 * 全局/局部/char/double/excess/标量字段/字段 excess/数组元素。
 */
#include <stdio.h>
int g1 = {42};
int g2 = {7, 8};
struct S { int n; char c; };
struct T { int g[2][2]; int n; };
int main(void) {
    int x = {5};
    char c = {'a'};
    double d = {1.5};
    int y = {9, 10};
    struct S s1 = {{7}, {'b'}};
    struct T t1 = {{1, 2}, {3}};
    int a[3] = {1, {2}, 3};
    printf("g=%d,%d x=%d c=%c d=%.1f y=%d\n", g1, g2, x, c, d, y);
    printf("s=%d,%c t=%d,%d,%d,%d,%d\n", s1.n, s1.c,
           t1.g[0][0], t1.g[0][1], t1.g[1][0], t1.g[1][1], t1.n);
    printf("a=%d,%d,%d\n", a[0], a[1], a[2]);
    return 0;
}
