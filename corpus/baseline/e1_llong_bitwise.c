// @category: baseline
// E1 B 档：long long 位运算（E3048 半成品缺陷修复）
#include <stdio.h>
int main() {
    long long x = 12, y = 10;
    unsigned long long u = 0xF000000000000000ULL;
    printf("%lld %lld %lld\n", x & y, x | y, x ^ y);
    printf("%lld %lld\n", ~x, x << 40);
    printf("%llu %llu\n", u >> 60, (unsigned long long)1 << 63);
    long long n = -8;
    printf("%lld %lld\n", n >> 1, n / 2);
    return 0;
}
