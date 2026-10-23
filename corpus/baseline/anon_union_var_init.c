/*
 * @category: declaration
 * 顶层匿名 union 变量声明带初始化器（#278 修复锚，2026-10-23）：C11 6.7.2.7
 * `union { int a; int b; } gu = { .b = 5 };` —— 匿名类型体 + 变量一体声明。
 * 旧 parse_aggregate_trailing_globals 恒 init:None 且不消费 '='，首错
 * E2005 落在声明器后 + 剩余 token 逐个炸顶层 UnexpectedTop（union 带声明器
 * 全落 trailing：classify 恒 UnionDecl；struct 对称形态被分到 StructVarOrFunc
 * 完整路径故不触发——两路径不对称是只咬 union 的原因）。修复 = trailing 补
 * init 解析（init_list/assign 与 parse_global_var_or_func 同款）。clang 真值
 * 对拍。
 */
#include <stdio.h>

union { int a; int b; } gu = { .b = 5 };
union U2 { int a; char c; } g2 = { 10 };              /* 具名 + init */
union { int a; int b; } ga[2] = { {1}, {2} };         /* 数组声明器 */
union { int a; int b; } x = {7}, y = {8};             /* 多声明器 */

int main(void) {
    printf("%d %d\n", gu.b, g2.a);        /* 5 10 */
    printf("%d %d %d %d\n", ga[0].a, ga[1].b, x.a, y.b);  /* 1 2 7 8 */
    return gu.b + g2.a;                   /* 15 */
}
