/*
 * @category: declarator_const
 * 函数指针声明符的指针自身 const（#296，2026-10-24）：int (* const fp)(…)
 * = const 函数指针（不可重绑定）。旧 interpret_declarator_node Function
 * 吸收臂丢弃声明符 `*` 的 is_const ⇒ typed AST is_const=false、重绑定
 * 零诊断（clang error: cannot assign to variable with const-qualified
 * type）；修复 = 传导到 decay 产物 Pointer(Function, true)，typeck
 * E3049 现成路径接上（重赋值红形态实测 vitro E3049 4:5 对齐 clang
 * 4:7 error，由 parser wbtest 双锚 + CLI 实测锚）。本语料锁合法面：
 * 首赋值 + 经 const 函数指针调用不回退；非 const 对照（重赋值合法）
 * 同文件覆盖。
 */
#include <stdio.h>

int add(int a, int b) { return a + b; }

int apply_const(int x) {
    int (* const fp)(int, int) = add;
    return fp(x, 2);
}

int apply_plain(int x) {
    int (*fp)(int, int) = add;
    fp = add;                    /* 非 const：重绑定合法（对照格）*/
    return fp(x, 5);
}

int main(void) {
    printf("%d %d\n", apply_const(40), apply_plain(30));
    return 0;
}
