// @category: ub_missing_return
// 非 void 函数缺 return 的 UB 结局差异锚（TheAlgorithms 对拍批 2026-10-25）：
// search() 递归调用无 return（doubly_linked_list.c 同款形态，语料原文）——
// C99 6.9.1p12：控制流到达非 void 函数结尾而不用 return，返回值未定义。
// clang -O0 实测输出 32758（eax 残留，随代码形状漂移；doubly_linked_list
// 原文件场景残留恰为 1）；Vitro 双臂恒 0。双侧皆合法值，本锚登记该族
// 「真值不可锚」形态——防未来对拍把缺 return 类分歧误报为引擎缺陷。
#include <stdio.h>
typedef struct l { double v; struct l *next; } L;
int search(L *n, double value) {
    if (n == NULL) return 0;
    if (n->v == value) return 1;
    search(n->next, value); /* missing return: UB (C99 6.9.1p12) */
}
int main(void) {
    L a = {3.0, 0}, b = {0.0, &a}, c = {20.0, &b};
    printf("%d\n", search(&c, 3.0));
    return 0;
}
