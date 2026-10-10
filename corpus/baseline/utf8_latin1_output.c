/* #66（2026-10-10）：Latin-1 范围字符（·=U+00B7 ×=U+00D7 等 C2 前缀段）
 * 输出损坏全链修复——根因三层：① 落盘 cstring Latin-1 单字节口径（· 落
 * 单字节 B7 与 clang 的 UTF-8 execution charset 分叉）→ 整串 UTF-8 直通；
 * ② printf fmt 装载 decode_lossy 对落盘字节二次解码错位；③ fputs/puts 的
 * lossy 对 / vm 臂逐字节折回 mojibake → 字节直推。四通道（printf/fputs/
 * puts/fprintf-stderr）+ CJK 混排与 clang 逐字节一致（stderr 走标记行被
 * 两防线剥离器剥、不入 stdout digest）。已知尾巴：sizeof 折叠对多字节
 * 字符串少计（另立）。 */
#include <stdio.h>
int main() {
    fputs("f·puts×\n", stdout);
    puts("p·line×");
    printf("A·X×Z 轻量\n");
    fprintf(stderr, "e·rr×\n");
    const char* s = "A·X";
    printf("bytes=%d %d %d %d\n", s[0] & 0xFF, s[1] & 0xFF, s[2] & 0xFF, s[3] & 0xFF);
    return 0;
}
