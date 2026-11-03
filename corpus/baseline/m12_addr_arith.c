// @category: baseline
// 绿锚（#437 即可入库批）：审阅 v2 M12 p06「地址族 8 项」无发现面——多维数组/struct 成员/void*/行指针的
// 字节偏移算术三方一致（clang/vitro js+native），入库锁防静默回归。来源：tmp/review_v2_M12/probes/p06_addr.c
#include <stdio.h>
struct S { int pad; char f[6]; };
int m[3][4];
struct S s;
int a[5];
int main(void) {
    int *p = a;
    printf("%d\n", (int)((char*)(p+3) - (char*)p));       /* 12 */
    printf("%d\n", (int)((char*)&m[2][3] - (char*)m));    /* 44 */
    printf("%d\n", (int)((char*)&s.f[3] - (char*)&s));    /* 7 */
    printf("%d\n", (int)((char*)&m[1] - (char*)m));       /* 16 */
    printf("%d\n", (int)((char*)((m[1])+2) - (char*)m));  /* 24 */
    char *cp = (char*)m;
    printf("%d\n", (int)((char*)(cp+5) - cp));            /* 5 */
    void *vp = &a[1];
    printf("%d\n", (int)((char*)((int*)vp+1) - (char*)vp)); /* 4 */
    int (*rp)[4] = m;
    printf("%d\n", (int)((char*)(rp+2) - (char*)m));      /* 32 */
    return 0;
}
