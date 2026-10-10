/* #61 审阅 P1-3（2026-10-10）：%u 符号面两处分叉——旧 u 臂不认 '-'（失败）
 * 且 '+' 被吃后 token 交 parse_uint（不吃 '+' → 写 0 还计数）；C 标准 %u
 * 匹配 strtoul 形态（符号合法、负值按无符号回绕）。对齐 i/x/o 臂形态。 */
#include <stdio.h>

int main() {
    unsigned a = 999;
    unsigned b = 999;
    int r1 = sscanf("-5", "%u", &a);
    int r2 = sscanf("+7", "%u", &b);
    printf("r1=%d a=%u r2=%d b=%u\n", r1, a, r2, b);
    return 0;
}
