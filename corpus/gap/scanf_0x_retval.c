/* #59 题 1 裁定分叉面：sscanf("0x","%i") 返回值——UCRT 把冲突当 EOF 返 -1，
 * 我们按 C11 匹配失败返已配数 0（glibc 2.43 实测同判 0）。行为面（不写/
 * 游标）双侧一致见 baseline/scanf_0x_behavior.c；本例只锁返回值派系差。
 * @category: arch_diff_bug */
#include <stdio.h>

int main() {
    int a = -99;
    int r = sscanf("0x", "%i", &a);
    printf("r=%d a=%d\n", r, a);
    return 0;
}
