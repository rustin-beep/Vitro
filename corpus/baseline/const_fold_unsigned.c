/*
 * @category: const_fold
 * 静态初始化器常量折叠的符号性（P1-2 审阅批修复锚，2026-10-18）：
 * 旧 const_eval 纯值域无符号位——比较/除法全走 Int64 有符号域、
 * CE_Cast 整型恒等丢 unsigned。clang 22.1.4 真值 1/1/0。
 */
#include <stdio.h>

unsigned int a = (0u - 1u) > 0;  /* u32 回绕巨值为真 */
int b = (unsigned)-1 > 0;        /* cast 无符号域为真 */
int c = -1 < 1u;                 /* usual conversions 升无符号域为假 */
unsigned int d = 6u / 2u;
unsigned int e = 0xFFFFFFFFu >> 28;
int f = (int)3.9;                /* 浮→整截断对照 */
unsigned int g = (unsigned char)-1; /* u8 零扩展 255 */

int main(void) {
    printf("%u %d %d\n", a, b, c);
    printf("%u %u\n", d, e);
    printf("%d %u\n", f, g);
    return 0;
}
