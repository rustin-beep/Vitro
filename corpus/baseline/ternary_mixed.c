// @category: baseline
// #9 销案形态语料（2026-10-06 审阅 P2-2 补）：三目混合数值 usual
// arithmetic conversions（int:double → double；unsigned:int 统一）
#include <stdio.h>
int main() {
    int x = 1;
    double d = x > 0 ? 2 : 3.5;
    unsigned u = 4;
    int i = u > 3 ? 5 : 0;
    printf("%.1f %d %d\n", d, i, (int)(x ? 1 : 2.5));
    return 0;
}
