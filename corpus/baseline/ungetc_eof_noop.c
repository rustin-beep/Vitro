/* #428 B5 批（2026-11-04）：ungetc(EOF) 无操作端到端锚——C11 §7.21.7.10
 * （失败含 EOF 实参时流不变，返回 EOF）。clang/UCRT + glibc 双派真值：
 * ungetc(EOF,stdin) 后 getchar 读流原内容 'x'=120（修前 vitro 把 -1
 * 当回退字节缓存回吐 → -1，吞一次读取——教学惯用法
 * ungetc(getchar(), stdin) 在 EOF 处踩）。正常 ungetc 往返对照。 */
#include <stdio.h>

int main() {
    int rc = ungetc(EOF, stdin);
    int c2 = getchar();
    printf("rc=%d c=%d\n", rc, c2);
    int c3 = getchar();
    int rc2 = ungetc('Q', stdin);
    int c4 = getchar();
    printf("c3=%d rc2=%d c4=%d\n", c3, rc2, c4);
    return 0;
}
