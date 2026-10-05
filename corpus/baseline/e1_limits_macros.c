// @category: baseline
// E1 B 档：limits.h 全宏（ULLONG_MAX 的 u64 位模式承载）
#include <stdio.h>
#include <limits.h>
int main() {
    printf("%d %d\n", INT_MAX, INT_MIN);
    printf("%llu %llu\n", (unsigned long long)UINT_MAX, (unsigned long long)ULONG_MAX);
    printf("%lld %lld\n", LLONG_MAX, LLONG_MIN);
    printf("%llu\n", ULLONG_MAX);
    printf("%d %d %d\n", CHAR_BIT, SCHAR_MIN, UCHAR_MAX);
    printf("%d %d\n", SHRT_MIN, USHRT_MAX);
    return 0;
}
