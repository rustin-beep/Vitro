// @category: baseline
// #135 修复锚（2026-10-17）：enum 常量作 case 标签——C11 §6.4.4.3 枚举
// 常量是整型常量表达式，typeck 常量性判定查不了枚举表（全局 VarDecl
// 同形不可区分），parser 在 case 标签位折叠 Ident → Literal 后放行。
// LLM 语料探针批四模型 8/8 命中形态。
#include <stdio.h>
enum { A = 1, B = 2 };
int main(void) {
    int x = 2;
    switch (x) { case A: printf("A\n"); break; case B: printf("B\n"); break; default: printf("?\n"); }
    switch (A) { case A: printf("lit-A\n"); break; }
    return 0;
}
