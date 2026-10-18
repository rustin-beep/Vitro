/*
 * @category: struct_init
 * 对抗批虫 α/β 修复锚（2026-10-18，随机分叉对抗挖出）：
 * α = 多维 char 字符串行部分填充——struct MD{char d[2][4];} v={"ab"}
 *   旧 typeck 按「多维须嵌套列表」拒（clang 零警告接受 [ab][]）；
 * β = 变量扁平流 elision——struct S2{char u[2][3];} fv={c,d,0,c,0,0}
 *   旧收紧面（全字面量）排除变量元素致 E3006（clang 接受）。
 */
#include <stdio.h>

struct MD { char d[2][4]; };
struct S2 { char u[2][3]; };

int main(void) {
    /* α：字符串行部分填充（首行 "ab"、次行零填） */
    struct MD v1 = {"ab"};
    printf("[%s][%s]\n", v1.d[0], v1.d[1]);
    struct MD v2 = {{"xy"}};
    printf("[%s][%s]\n", v2.d[0], v2.d[1]);

    /* β：变量扁平流（char 数组字段） */
    char c = 'p';
    char d = 'q';
    struct S2 fv = {c, d, 0, c, 0, 0};
    printf("[%s][%s]\n", fv.u[0], fv.u[1]);

    /* β 对照：int 数组字段的变量扁平流 */
    struct MI { int g[2][2]; };
    int x = 7;
    struct MI mi = {x, x + 1, x * 2, x - 1};
    printf("%d,%d,%d,%d\n", mi.g[0][0], mi.g[0][1], mi.g[1][0], mi.g[1][1]);
    return 0;
}
