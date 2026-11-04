/* #428 B5 批（2026-11-04）：scanf 数字转换超域 clamp 边界位模式端到端锚。
 * clang/UCRT + glibc 双派真值（修前 vitro 全归 0 / i·x·o 裸回绕）：
 * - %d 正超域 → ULLONG_MAX 低 32 位 = -1；%d 负超域 → LLONG_MIN 低 32 位 = 0
 * - %lld 正超域 → LLONG_MAX；负超域 → LLONG_MIN
 * - %llu 负超域 → ULLONG_MAX（负号吞——clamp 压过回绕）
 * - 窄档取 clamp 低位（%hd → 0xFFFF；%hhu → 0xFF；%hu → 0xFFFF）
 * - 域内截断（4294967297 %d → 1）与域内负号回绕（-5 %u → 4294967291）
 *   防误翻（速查表 S3——现状本来就对） */
#include <stdio.h>

int main() {
    int a = -7;
    long long c = -7;
    unsigned long long d = 7;
    int r = scanf("%d %lld %llu", &a, &c, &d);
    printf("r=%d a=%d c=%lld d=%llu\n", r, a, c, d);
    int e = -7;
    short h = -7;
    unsigned short hu = 7;
    r = scanf("%d %hd %hu", &e, &h, &hu);
    printf("r=%d e=%d h=%d hu=%u\n", r, e, h, hu);
    int in_range = -7;
    unsigned neg_in_range = 7;
    r = scanf("%d %u", &in_range, &neg_in_range);
    printf("r=%d in=%d u=%u\n", r, in_range, neg_in_range);
    /* sscanf 壳：负超域 %llx 负号吞（修前裸回绕 0） */
    unsigned long long lx = 7;
    r = sscanf("-10000000000000000", "%llx", &lx);
    printf("ss r=%d lx=%llu\n", r, lx);
    return 0;
}
