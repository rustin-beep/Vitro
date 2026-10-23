/*
 * @category: designated_init
 * struct/union designated initializer 全层（#270 修复锚，2026-10-22）：
 * C99 §6.7.8p35 的 .field 指派——文件作用域/嵌套子列表/局部 static/
 * 匿名成员穿透/乱序与部分初始化（未提及位零填）全形态；数组 [i]=
 * 指派与混合续位（#76 面）回归。旧形态：全局 struct 一律「仅支持数组
 * 目标」拒绝、局部 static 拒绝、嵌套子列表 designator 被位置序错位、
 * 匿名穿透偏移按 struct 累加（union 应恒 0）。clang 真值对拍。
 */
#include <stdio.h>

struct Inner { int a, b; };
struct Outer { int tag; struct Inner in; };
struct AnonU { int pre; union { int u1; float u2; }; };

static struct Outer g1 = { .in = { .b = 7, .a = 6 }, .tag = 5 };
static struct AnonU g2 = { .pre = 1, .u2 = 1 };
static struct AnonU g3 = { .u1 = 42 };
static struct Inner partial = { .b = 3 };          /* 部分初始化：a 零填 */
static int tbl[6] = { [2] = 5, 6, [0] = 1 };       /* 数组指派 + 续位（#76） */

static int counter(void) {
    static struct Inner s = { .b = 9 };            /* 局部 static 指派 */
    s.a += 1;
    return s.a * 100 + s.b;
}

struct Deep {
    int a;
    struct { int b; struct { int c; int d; }; };   /* 嵌套 >=2 层匿名 */
};
static struct Deep gdeep = { .d = 9 };            /* 审阅 P1-2：深层偏移 */
typedef int (*AF)(int);
static int a1(int x) { return x + 1; }
static int a2(int x) { return x + 2; }
static AF faddr[2] = { &a1, &a2 };                /* 审阅 P1-4：&f 全局数组 */
static AF fsingle = &a1;                          /* 审阅 P1-4：&f 全局标量 */
union V { int x; int y; };

int main(void) {
    struct Deep d = { .d = 9 };
    printf("deep=%d %d %d %d\n", d.a, d.b, d.c, d.d);
    struct Inner li = { .b = 7, .a = 6 };         /* 审阅 P1-3：局部乱序 */
    printf("li=%d %d\n", li.a, li.b);
    union V v = { .y = 1 };                       /* 审阅 P1-3 连坐：union 非首成员 */
    printf("v=%d\n", v.y);
    struct Inner p2 = { .a = 1, 2 };               /* 审阅 P2-3：混合续位 */
    printf("mix=%d %d\n", p2.a, p2.b);
    printf("g1=%d %d %d\n", g1.tag, g1.in.a, g1.in.b);
    printf("g2=%d %d\n", g2.pre, g2.u1);           /* u1 视图读 u2 位模式 */
    printf("g3=%d partial=%d %d\n", g3.u1, partial.a, partial.b);
    printf("tbl=%d %d %d %d\n", tbl[0], tbl[2], tbl[3], tbl[5]);
    printf("s=%d %d\n", counter(), counter());
    struct Outer loc = { .in = { .a = 4 }, .tag = 8 }; /* 局部指派 + 嵌套 */
    printf("loc=%d %d\n", loc.tag, loc.in.a);
    return 0;
}
