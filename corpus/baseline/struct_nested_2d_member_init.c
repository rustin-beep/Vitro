/*
 * @category: struct_init
 * struct 成员多维数组初始化双形态（#179/#180 修复锚，2026-10-18）：
 * #179 嵌套大括号——gen_nested_init 步长旧用 base 元素 4（应为行 12），
 * {{1,2,3},{4,5,6}} 得 1,4,5,6,0,0；#180 扁平 elision（C99 6.7.9p20）
 * ——typeck 位置路径重组 + codegen 扁平流 base 步进，旧报 E3006 误拒。
 */
#include <stdio.h>

struct M { int d[2][3]; };
struct M3 { int d[3][3]; };
struct MC { char d[2][4]; };
struct Two { int n; int d[2][3]; };

int main(void) {
    struct M a = {{{1, 2, 3}, {4, 5, 6}}};     /* #179 嵌套 */
    for (int i = 0; i < 2; i++)
        for (int j = 0; j < 3; j++) printf("%d,", a.d[i][j]);
    printf("\n");

    struct M f = {1, 2, 3, 4, 5, 6};           /* #180 扁平 elision */
    for (int i = 0; i < 2; i++)
        for (int j = 0; j < 3; j++) printf("%d,", f.d[i][j]);
    printf("\n");

    struct M3 b = {{{1, 2, 3}, {4, 5, 6}, {7, 8, 9}}};
    for (int i = 0; i < 3; i++)
        for (int j = 0; j < 3; j++) printf("%d,", b.d[i][j]);
    printf("\n");

    struct MC c = {{"ab", "cd"}};              /* char 行字符串形态 */
    printf("[%s][%s]\n", c.d[0], c.d[1]);

    struct Two t = {9, 1, 2, 3, 4, 5, 6};      /* 标量字段 + 扁平流 */
    printf("%d|", t.n);
    for (int i = 0; i < 2; i++)
        for (int j = 0; j < 3; j++) printf("%d,", t.d[i][j]);
    printf("\n");

    struct Two p = {1, 2, 3};                  /* 部分填充（余零填） */
    printf("%d|%d,%d,%d,%d,%d,%d\n", p.n, p.d[0][0], p.d[0][1],
           p.d[0][2], p.d[1][0], p.d[1][1], p.d[1][2]);
    return 0;
}
