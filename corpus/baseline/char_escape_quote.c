/*
 * @category: lexer
 * 字符常量的简单转义序列全集（#181 修复锚，2026-10-18）：char 侧
 * simple 表旧漏转义双引号（C11 6.4.4.4——字符串侧早有），'\"' 落
 * 「未知字符转义」E1001 误拒。七对全集 + 可选双引号逐个对照。
 */
#include <stdio.h>

int main(void) {
    char dq = '"';
    char sq = '\'';
    char bs = '\\';
    char q_esc = '\"';
    char nl = '\n';
    char tb = '\t';
    printf("dq=%c sq=%c bs=%c qe=%c nl=%d tb=%d\n", dq, sq, bs, q_esc,
           nl, tb);
    return 0;
}
