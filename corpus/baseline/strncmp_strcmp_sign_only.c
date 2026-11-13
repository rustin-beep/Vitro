// @category: baseline
// #510 同塘 A2：strncmp/strcmp 返回值**符号**锚——C 标准（C11 §7.24.4）只
// 锁符号，派系（vitro glibc 字节差 23 vs 本机 UCRT 归一 1）两侧都合法、
// 选边待拍板（issue #510）。拍板前语料只锁符号不锁值；锚对差值刻意取
// |diff|≠1（0xff vs 0xe8 差 23）——strcmp("a","b") 差恰 -1 与归一值同，
// 是假一致锚（两侧同值掩盖派系分歧），勿用。
#include <stdio.h>
#include <string.h>
int main() {
    printf("%d %d\n", strncmp("a\xff", "a\xe8", 8) > 0, strncmp("a\xe8", "a\xff", 8) < 0);
    printf("%d %d\n", strcmp("zz\xff", "zz\xe8") > 0, strcmp("zz\xe8", "zz\xff") < 0);
    printf("%d\n", strncmp("abc", "abd", 2) == 0);
    return 0;
}
