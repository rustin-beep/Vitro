/*
 * @category: libc_string
 * memchr 负 c / 0xFF 查找（#166 修复锚，2026-10-18）：
 * C11 §7.24.5.1——c 参数「转换为 unsigned char 后比较」，负 c（-1 ≡ 0xFF）
 * 必命中同值字节；旧实现对负 c 裸 i32 比较恒不中（strchr 病 1 未连坐）。
 * 0xFF 字节一律运行期构造（字面量 \xFF 通道是 #166 缺陷 B 已知差异面，
 * 勿在此用例引入）。
 */
#include <stdio.h>
#include <string.h>

int main(void) {
    char s[8] = "abcdefg";
    s[3] = (char)-1; /* 0xFF 字节（运行期构造，绕开字面量编码面） */

    char *r = memchr(s, -1, 8); /* 负 c 转 unsigned char 命中偏移 3 */
    printf("neg=%d\n", r ? (int)(r - s) : -1);

    char *q = memchr(s, 0xFF, 8); /* 255 正数形态查同一字节 */
    printf("ff=%d\n", q ? (int)(q - s) : -1);

    char *p = memchr(s, 'e', 8); /* 纯 ASCII 正向对照 */
    printf("e=%d\n", p ? (int)(p - s) : -1);

    char *m = memchr(s, 'Z', 8); /* 未命中返 NULL */
    printf("miss=%d\n", m ? (int)(m - s) : -1);

    char *z = memchr(s, 'a', 0); /* n=0 恒 NULL 边界 */
    printf("n0=%d\n", z ? (int)(z - s) : -1);

    return 0;
}
