/*
 * @category: baseline
 * union 按值实参 + 按值返回（#515 修复锚，2026-11-15）：`takeU(u)` 直接
 * 标识符传 / `takeU(*up)` 解引用传 / `makeU()` 按值返回初始化。缺陷版
 * （聚合判定漏 TK_Union 七处）：前两形态实参落标量臂只压 1 word（gen_expr
 * 压 union 变量地址），callee 形参区按 type_size=8 的 words=2 读参 → 栈
 * 下溢 TRAP L11/L12（三臂同病）；返回形态落「不支持的地址生成」编译错
 * L13（gen_addr 的 CallPtr 臂只判 TK_Struct）。clang 真值对拍。
 */
#include <stdio.h>

typedef union { int i; double d; } U;

int takeU(U u) { return u.i; }
U makeU(int x) { U u; u.i = x; return u; }

int main(void) {
    U u; u.i = 7;
    U *up = &u;
    printf("byval=%d\n", takeU(u));       /* 7 */
    printf("deref=%d\n", takeU(*up));     /* 7 */
    U v = makeU(7);
    printf("ret=%d\n", v.i);              /* 7 */
    u.d = 1.5;                            /* 换写 double 成员——8 字第二 word 真实装载 */
    printf("d=%g\n", u.d);                /* 1.5 */
    return 0;
}
