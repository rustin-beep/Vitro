// @category: ub_missing_return
// 非 void 函数缺 return 的 UB 结局差异锚（2026-10-25 立；2026-10-30 审计批
// 改写为独立表达——原锚形态观察自外部 GPL 语料库，本仓不携带其文本）：
// C99 6.9.1p12：控制流到达非 void 函数结尾而不用 return，返回值未定义。
// 原锚 clang -O0 实测输出 32758（eax 残留，随代码形状漂移——改写后残值
// 以重冻 digest 为准）；Vitro 双臂恒 0。双侧皆合法值，本锚登记该族
// 「真值不可锚」形态——防未来对拍把缺 return 类分歧误报为引擎缺陷。
#include <stdio.h>

typedef struct cell {
    int key;
    struct cell *tail;
} chain;

int walk(chain *p, int target) {
    if (p == 0) return 0;
    if (p->key == target) return 1;
    walk(p->tail, target); /* missing return: UB (C99 6.9.1p12) */
}

int main(void) {
    chain last = {7, 0};
    chain mid = {4, &last};
    chain head = {9, &mid};
    printf("%d\n", walk(&head, 4));
    return 0;
}
