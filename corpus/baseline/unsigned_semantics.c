#include <stdio.h>
#include <string.h>

// @category: unsigned 语义全家桶（#71 病 30~34 修复批锚用例）
// 病 30 整型提升 / 31 U 系转换 / 32 uchar 零扩展读 / 33 char 窄化 /
// 34 ULL 域除模比较复合赋值——修复前五形态全错，双臂对拍 clang 真值。

int main() {
    // 病 30：uchar 提升为 signed int（(c-1)/2 = 0 而非 2147483647）
    unsigned char c = 0;
    printf("%d\n", (c - 1) / 2);
    // 病 30：uint vs LL 不传播 unsigned（i64 ⊇ u32 → signed LL）
    unsigned u = 500000000;
    printf("%lld\n", u - 5000000000LL);
    // 病 31：u32 → i64 零扩展（4294967295 而非 -1）
    unsigned u2 = 4294967295u;
    printf("%lld\n", (long long)u2);
    // 病 31：u32 → double 零符号位（3000000000.0 而非负值）
    unsigned u3 = 3000000000u;
    printf("%f\n", (double)u3);
    // 病 32：unsigned char 数组元素/解引用零扩展（AB 而非 FFFFFFAB）
    unsigned char buf[4];
    memset(buf, 0xAB, 4);
    printf("%08X\n", buf[0]);
    unsigned char *p = buf;
    printf("%08X\n", *p);
    // 病 33：char 窄化截断（200 → -56；300 → 44；unsigned 300 → 44）
    char c2 = 200;
    printf("%d\n", c2);
    signed char sc = 300;
    printf("%d\n", sc);
    unsigned char uc = 300;
    printf("%d\n", uc);
    // 病 34：ULL 比较（2^63 > 0 = 1，signed 域为 0）
    unsigned long long a = 9223372036854775808ULL;
    printf("%d\n", a > 0);
    // 病 34：ULL 复合移位（<<= 40 走 Q 域而非 32 位 trap）
    unsigned long long x = 1;
    x <<= 40;
    printf("%llu\n", x);
    // 病 34：ULL 复合位与（Q 域保高 32 位）
    unsigned long long y = 0xFFFFFFFFFFFFFFFFULL;
    y &= 0xFFFFFFFF00000000LL;
    printf("%llX\n", y);
    // 病 34：ULL 除/模（UDivQ/UModQ 域）
    unsigned long long d = 18446744073709551615ULL;
    printf("%llu %llu\n", d / 3, d % 7);
    // 病 34：ULL 四关系（全无符号域）
    printf("%d %d %d %d\n", d > 3, d >= 18446744073709551615ULL, d < 3, d <= 1);
    // 病 117（≡59）：u 后缀 INT_MAX<x≤UINT_MAX 按 C11 6.4.4.1 定型 unsigned int
    // ——sizeof=4（修复前 ULL 定型错值 8）+ uint 域乘法环回 + W3053 假阳性清零
    printf("%d %u\n", (int)sizeof(3000000000u), 3000000000u * 2u);
    return 0;
}
