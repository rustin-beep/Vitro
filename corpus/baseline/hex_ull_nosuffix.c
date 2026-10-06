// @category: baseline
// #24 销案形态语料（2026-10-06 审阅 P2-2 补）：无后缀 hex 超 i64 档
//（C11 §6.4.4.1 候选序列含 unsigned long long——BLAKE2b IV 级两档）
#include <stdio.h>
int main() {
    unsigned long long k = 0xABCDEF0123456789;
    unsigned long long m = 0xFFFFFFFFFFFFFFFF;
    printf("%llu %llu %llu\n", k, m, k ^ m);
    return 0;
}
