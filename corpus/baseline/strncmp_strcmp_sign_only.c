// @category: baseline
// #510 同塘 A2：strncmp/strcmp **unsigned char 比较序**锚——C11 §7.24.4
// 明文规定按 unsigned char 解释逐字节比较："\x80" vs "\x01" 无符号序
// 128>1 得 1（若实现误按 signed char 比较得 -128<1 → 0 即红——比返回值
// 派系更硬的轴）。派系（vitro glibc 字节差 23 vs 本机 UCRT 归一 1，两侧
// 均合法）已拍板维持 glibc 字节差（#510 评论 2026-11-13）；布尔化输出下
// 派系分歧在幅度、符号两侧恒同——裸值锚待将来有需要时另立（勿用
// strcmp("a","b")：差恰 -1=归一值，是假一致锚）。
#include <stdio.h>
#include <string.h>
int main() {
    printf("%d %d\n", strncmp("\x80", "\x01", 1) > 0, strncmp("\x01", "\x80", 1) < 0);
    printf("%d %d\n", strcmp("zz\x80", "zz\x01") > 0, strcmp("zz\x01", "zz\x80") < 0);
    printf("%d %d\n", strncmp("a\xff", "a\xe8", 8) > 0, strncmp("a\xe8", "a\xff", 8) < 0);
    printf("%d\n", strncmp("abc", "abd", 2) == 0);
    return 0;
}
