// @category: baseline
// #4 销案形态语料（2026-10-06 审阅 P2-2 补）：初始化列表尾逗号
//（C89/C11 §6.7.9 合法——含嵌套与 designator 形态）
#include <stdio.h>
struct P { int x, y; };
int main() {
    int a[3] = {1, 2, };
    struct P p = {3, 4, };
    int b[2][2] = {{1, 2, }, {3, 4, }, };
    printf("%d %d %d %d %d\n", a[0] + a[1], p.x + p.y, b[0][1], b[1][0], b[1][1]);
    return 0;
}
