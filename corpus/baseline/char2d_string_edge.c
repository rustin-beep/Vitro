// @category: baseline
// #137 缺陷 1 边界锚（2026-10-17）：static 局部二维 / 越界截断
//（W3008 警告 + 截断语义对齐 clang [-Wexcess-initializers]）/
// 部分初始化零填充三形态。
#include <stdio.h>
int main(void) {
    static char st[2][8] = { "pq", "rs" };
    printf("static: [%s][%s]\n", st[0], st[1]);
    char w[2][4] = { "toolong", "ok" };
    printf("trunc: [%s][%s]\n", w[0], w[1]);
    char g[2][8] = { "mn" };
    printf("partial: [%s][%s]\n", g[0], g[1]);
    return 0;
}
