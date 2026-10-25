/*
 * @category: lexer_column
 * token 起始列快照锚（#297，2026-10-24）：text 为规范化值的数字 token
 * （0x1F→"31" / 0b101→"5" / 07→"7" / 5000000000U 后缀剥）列 = 源拼写
 * 起始列——旧「扫描后列 − 规范化 text 字节数」回推必偏（0x1F +2、
 * 0b101 +4、07 +1、后缀 +1，少减的字节数即偏差；E3074 实测 vitro
 * 5:16 vs clang 5:14）。行拼接字符串 token 的 loc = 起始行列（旧回推
 * 跨过换行列重置点——issue 实测负列）。列字段由 L1 TSV digest 锁位；
 * 输出对拍 clang（1'000 分隔符形态 clang_direct 无 -std（gnu17）下
 * 编译失败不入本语料，由 scanner wbtest 锁）。
 */
#include <stdio.h>

int main(void) {
    int hex = 0x1F;
    int bin = 0b101;
    int oct = 07;
    unsigned long long big = 5000000000U;
    const char *s = "ab\
cd";
    printf("%d %d %d %llu %s\n", hex, bin, oct, big, s);
    return 0;
}
