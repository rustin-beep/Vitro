// @category: baseline
// DIFF-LIB-ATOF-01 锚（2026-10-05 批二-a）：atof 取最长浮点前缀（C atof≡strtod(str,NULL)）——"12abc"→12.0；旧整串 parse 失败→0.0 系 oracle 照搬
#include <stdio.h>
#include <stdlib.h>
int main() {
    printf("%.1f %.1f %.1f\n", atof("12abc"), atof("-2.5e1xyz"), atof("xyz"));
    return 0;
}
