/* issue #251 翻案（2026-10-28）：十进制**无后缀**大常量（INT64_MAX < v
 * ≤ ULLONG_MAX）收 ULL 档——推翻 DIFF-LEX-DECL-BIGCONST-01 2026-10-04
 * 「保持 error」裁定。C11 6.4.4.1 十进制无后缀候选序全有符号、超出即
 * 实现定义；clang/gcc 双实现均 warning + 收 unsigned long long（rc=0）。
 * 旧 vitro 对全格报 E1006 拒绝（djb2 比较值/ULLONG_MAX 真实语料在用）。
 * 判别式直比不转存（同 u_suffix_unsigned_domain.c 审阅 P2-1 口径：
 * 转存格位模式赋值转换会抹掉符号域差异）。 */
#include <stdio.h>
int main(void) {
    printf("%d\n", 13827776004929097857 > 100);
    printf("%llu\n", 18446744073709551615);
    printf("%llu\n", 9223372036854775808 - 1);
    /* PR #345 审阅 P1：u64→fp 转换面（判等锚定位模式——printf %.17g
     * 打印末位另有 ULP 独立面不入锚）。旧形态 (double)ULL 走 CastQ2D
     * 有符号解释产 -1（含隐式初始化/混合运算/static 折叠全链错值）。 */
    printf("%d\n", (double)18446744073709551615 == 18446744073709551615.0);
    printf("%d\n", 18446744073709551615 + 0.5 > 1e19);
    double d = 18446744073709551615;
    printf("%d\n", d == 18446744073709551615.0);
    float f = 18446744073709551615ULL;
    printf("%d\n", f == f);
    return 0;
}
