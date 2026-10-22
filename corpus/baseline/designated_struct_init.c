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

int main(void) {
    printf("g1=%d %d %d\n", g1.tag, g1.in.a, g1.in.b);
    printf("g2=%d %d\n", g2.pre, g2.u1);           /* u1 视图读 u2 位模式 */
    printf("g3=%d partial=%d %d\n", g3.u1, partial.a, partial.b);
    printf("tbl=%d %d %d %d\n", tbl[0], tbl[2], tbl[3], tbl[5]);
    printf("s=%d %d\n", counter(), counter());
    struct Outer loc = { .in = { .a = 4 }, .tag = 8 }; /* 局部指派 + 嵌套 */
    printf("loc=%d %d\n", loc.tag, loc.in.a);
    return 0;
}
