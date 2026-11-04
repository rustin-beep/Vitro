// @category: baseline
// 绿锚（#437 即可入库批）：审阅 v2 M12 p10「自增族」无发现面——前/后缀自增自减、*p++/*++p、
// char/uchar 回绕、LL 边界三方一致。注意 ll++ 行为 UB 域（clang x86 回绕，vitro 同形——教学口径锁定）。
// 来源：tmp/review_v2_M12/probes/p10_incdec.c
#include <stdio.h>
int main(void) {
    int i = 3;
    int a = i++;   /* 3, i=4 */
    int b = ++i;   /* 5, i=5 */
    int c = i--;   /* 5, i=4 */
    int d = --i;   /* 3, i=3 */
    printf("%d %d %d %d %d\n", a, b, c, d, i);
    int arr[3] = {10,20,30};
    int *p = arr;
    int e = *p++;  /* 10, p->arr[1] */
    int f2 = *++p; /* 30, p->arr[2] */
    printf("%d %d\n", e, f2);
    char ch = 127;
    ch++;          /* -128 */
    unsigned char uc = 255;
    uc++;          /* 0 */
    printf("%d %d\n", ch, uc);
    long long ll = 9223372036854775807LL;
    ll++;          /* UB；clang 回绕 -9223372036854775808 */
    printf("%lld\n", ll);
    return 0;
}
