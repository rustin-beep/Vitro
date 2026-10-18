// 静态存储期初始化器的常量表达式求值（#142 红锚，2026-10-18）：
// 文件作用域与函数内 static 的算术/宏/sizeof 表达式初始化器应正确求值
// （修复前静默置 0）；enum 常量参与同折（#142 连坐）。局部非 static
// 运行时求值形态作对照。
#include <stdio.h>
#define D 5
int g_expr = 3 + 5;
static int s_expr = 2 * 3;
int t_expr[] = {1 + 1, 2 * 2, 3 * 3};
const int c_expr = 10 - 2;
int u_macro = D + 1;
enum E { EA = 5, EB = 10 };
int v_enum = EB + 1;
int w_sizeof[4];
int main(void) {
    static int ls = 2 * 3;
    static int larr[3] = {1 + 1, 2 * 2, 3 * 3};
    int local = 2 * 3;
    printf("g=%d s=%d t=%d,%d,%d c=%d u=%d\n", g_expr, s_expr, t_expr[0],
           t_expr[1], t_expr[2], c_expr, u_macro);
    printf("v=%d w=%d ls=%d la=%d,%d local=%d\n", v_enum,
           (int)(sizeof(w_sizeof) / sizeof(w_sizeof[0])), ls, larr[0],
           larr[1], local);
    return 0;
}
