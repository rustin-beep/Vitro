/* issue #251 同族格（2026-10-24 修）：U/UL 后缀超 u32 档的符号域。
 * C11 6.4.4.1 U 后缀候选序全无符号（unsigned int → unsigned long →
 * unsigned long long；LLP64 前两者 4B）——值 >4B 定型 unsigned long
 * long。旧词法对中档（u32 < v ≤ i64）发有符号 8B token（LongLiteral）。
 * 运行期判别式必须**直比不转存**（审阅 P2-1：赋给 unsigned long long
 * 变量再比较时，位模式赋值转换会抹掉符号域差异——旧实现在转存格下
 * 输出与本格相同；直比格旧实现 0 / clang 与修复版 1）。注：十进制
 * **无后缀**大常量的 E1006 维持（DIFF-LEX-DECL-BIGCONST-01 台账裁定，
 * 翻案挂 #251 待拍板）——与本格「U 后缀候选全无符号」标准地位不同。 */
#include <stdio.h>
int main(void) {
    printf("%d\n", (5000000000U - 6000000000U) > 0);
    printf("%llu\n", 0x1FFFFFFFFu / 2);
    return 0;
}
