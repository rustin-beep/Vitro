/*
 * @category: compound_literal
 * 数组复合字面量作指针初始化值（#272 修复锚，2026-10-23）：C99 6.5.2.5
 * `int *p = (int[]){10, 20};` —— p 指向物化的匿名对象。旧 emit_local_init
 * 对 TK_Array 字面量沿标量路径 LoadMem，把 gen_expr 留下的对象地址当可读
 * 内存 load 出首元素存给 p——p 持元素值，p[i] 变成解引用小整数地址（探针
 * 实测 trap 地址 0x10 / 复杂上下文静默错值）。与 #267（左值语义）分型：
 * 本条是值语义消费面。clang 真值对拍。
 */
#include <stdio.h>

int main(void) {
    int *p = (int[]){10, 20};
    printf("%d %d\n", p[0], p[1]);         /* 10 20 */
    char *s = (char[]){'h', 'i', '\0'};
    printf("%s\n", s);                     /* hi */
    int a = (int[]){30, 40}[1];            /* 直接下标消费 */
    int q = *(int[]){1, 2} + *(int[]){3, 4};
    printf("%d %d\n", a, q);               /* 40 4 */
    return p[1] + (int)s[0];               /* 124 */
}
