/*
 * @category: comma_expr
 * 逗号运算符的四值形态（#248 修复锚，2026-10-22）：旧 codegen 对
 * Comma 无条件发 Swap+Pop——void 操作数不压值，`g(1), g(2);` 语句
 * 栈空触发下溢守卫虚假 TRAP「Swap: 栈不足」（输出正确但 rc=2、后续
 * 语句截断）。按左值是否在场分流后的全形态对照。clang 真值对拍。
 */
#include <stdio.h>

void g(int x) { printf("%d ", x); }
int side(void) { printf("s "); return 9; }

int main(void) {
    /* 双 void（issue 主形态：旧 TRAP 面） */
    g(1), g(2);
    printf("| ");
    /* 左值 + 右 void */
    int y = 0;
    (y = 5), g(y);
    printf("y=%d | ", y);
    /* 左 void + 右值（表达式语境取值） */
    int z = (g(3), 7);
    printf("z=%d | ", z);
    /* 双值（既有 Swap+Pop 路径回归） */
    int w = (3, 4);
    printf("w=%d | ", w);
    /* 三连 void + 嵌套值 */
    g(4), g(5), g(6);
    int v = (g(7), (side(), 8));
    printf("v=%d\n", v);
    return 0;
}
