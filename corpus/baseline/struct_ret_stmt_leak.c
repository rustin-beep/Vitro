#include <stdio.h>

// @category: struct 返回值表达式语句栈平衡（#71 病 36 修复批锚用例）
// 表达式语句 make(); 的 struct 表达式值（sret 地址槽）此前不弹栈——
// 循环 10001 次必触值栈溢出（MAX_STACK_DEPTH=10000）；clang 真值 ok。

struct P { int a, b; };

struct P make(void) {
    struct P p = {1, 2};
    return p;
}

int main() {
    int i = 0;
    while (i < 10001) {
        make();
        i = i + 1;
    }
    printf("ok %d\n", i);
    struct P s = make();
    printf("%d %d\n", s.a, s.b);
    s = make();
    printf("%d %d\n", s.a, s.b);
    return 0;
}
