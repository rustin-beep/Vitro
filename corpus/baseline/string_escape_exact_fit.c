// @category: baseline
// 绿锚（#437 修复后入库批）：速查表 E5/E6/E7 行——\xff 转义字节口径计长的恰满形态：char s[2]
// = "\xff" 恰满零警（修前按 UTF-8 计 2 字节 + NUL → W3008 假警）、char g[] = {"\xff"} 定型
// 尺寸 2（修前 3）、char w[1][2] 行恰满零警。B6 批（#429，2026-11-03 字面量承载治本）修复后
// 翻面入桶；值面（字节内容/strlen/strspn）由 string_escape_latin1_bytes.c 锁、全局恰满形态由
// string_escape_nul_term.c 锁（B6 修复后其口径同步翻面）——本文件锁局部一维/二维定型面。
// 来源：tmp/review_v2_M09 D1 / A2 锚 A9/A10。
#include <stdio.h>
char g[] = {"\xff"};
int main(void) {
    char s[2] = "\xff";
    char w[1][2] = {"\xff"};
    printf("sz=%d s0=%02X\n", (int)sizeof(g), (unsigned char)s[0]);   // clang: sz=2 s0=FF
    (void)w;
    return 0;
}
