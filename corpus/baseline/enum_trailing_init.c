/*
 * @category: declaration
 * enum trailing 声明器带初始化器（PR #282 审阅 P2-1 修复锚，2026-10-23）：
 * C11 6.7.2.2 `enum { A, B } e = B;` —— enum 定义体后声明器组与 struct/union
 * 同构。旧 parse_enum_decl 的孪生 trailing 循环恒 init:None 且不消费 '='
 * （E2005「enum 声明后预期 ';'」+ UnexpectedTop 级联）——#278 只修了
 * aggregate 侧孪生实现（parse_aggregate_trailing_globals），本条补齐
 * enum 侧（C5 同族面：聚合体后声明器组三份孪生实现）。clang 真值对拍。
 */
#include <stdio.h>

enum { A, B } e = B;                      /* 匿名 + 枚举常量 init */
enum Tag { T1 = 5, T2 } t = T2;           /* 具名 tag + 越位常量 */
enum { C1, C2 } m = { 1 }, n;             /* 多声明器：带 init 与裸声明器混排 */

int main(void) {
    printf("%d %d %d %d\n", e, t, m, n);  /* 1 6 1 0 */
    return e + t;                         /* 7 */
}
