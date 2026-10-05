// @category: baseline
// DIFF-LIB-ATOF-01 锚（2026-10-05 批二-a；同日审阅 P2-1 补强）：atof 取最长
// 合法前缀（C atof≡strtod(str,NULL)）——悬空指数回退（1e/1e+→1）+ C99 hex
// float（0x10→16 / 0x1p4→16 / 0x.8p1→1 / 0x1p-2→0.25）；旧整串 parse 失败
// →0.0 系 oracle 照搬
#include <stdio.h>
#include <stdlib.h>
int main() {
    printf("%.1f %.1f %.1f\n", atof("12abc"), atof("-2.5e1xyz"), atof("xyz"));
    printf("%.4g %.4g %.4g\n", atof("1e"), atof("1e+"), atof("1e-"));
    printf("%.4g %.4g %.4g %.4g\n", atof("0x10"), atof("0x1p4"), atof("0x.8p1"), atof("0x1p-2"));
    return 0;
}
