// @category: baseline
// 绿锚（#437 修复后入库批）：速查表 Z5/Z6 行——! 的判零数值域：-0.0f 位模式非零但数值等于
// 0（! 应 1）、0x100000000LL 低 32 位为零（! 应 0）。B2 批（#425，2026-11-03）修复 Not 截断
// 判零（CastF2I/Q2I 截断改数值 != 0）后翻面入桶；&&/||/while/tern 臂由 logic_judge_zero.c 锁。
// 来源：tmp/review_v2_M13/probes p14 / V1 表；翻面批 #425。
#include <stdio.h>
int main(void) {
    printf("%d\n", !(-0.0f));       // clang: 1（-0.0 数值等于 0）
    printf("%d\n", !0x100000000LL); // clang: 0（LL 非零）
    return 0;
}
