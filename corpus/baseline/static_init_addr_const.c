/*
 * @category: static_addr_const
 * 静态初始化器的地址常量（#264 修复锚，2026-10-22）：数组名退化为指向
 * 首元素的指针（C23 §6.6p9 地址常量）、&g 取址族——静态规格表互引用的
 * 标准写法。旧 E3075 误把数组名当「变量引用」误拒；诊断放行后 codegen
 * 亦缺地址回填（静默 0 → 运行 trap）。clang 真值对拍。
 */
#include <stdio.h>

static const char X[] = "hello";
static const char Y[] = "world";
static int g = 7;

typedef struct {
    const char *name;
    const char *data;
    int len;
} Entry;

/* 静态表引用另一张表：数组名作初始化器（issue 主形态：E3075 误拒面） */
static const Entry TABLE[2] = {
    { "first", X, 5 },
    { "second", Y, 5 },
};

/* 一维数组名直接初始化 char*（同形态） */
static const char *pick = Y;

/* &g 地址常量（诊断已放行、值回填缺口面） */
static int *gp = &g;

/* 函数名地址常量对照（既有路径回归锚） */
static int twice(int v) { return v * 2; }
static int (*fp)(int) = twice;

int main(void) {
    printf("%s %s\n", TABLE[0].data, TABLE[1].data);
    printf("%s\n", pick);
    printf("gp=%d\n", *gp);
    printf("fp=%d\n", fp(21));
    printf("first=%s len=%d\n", TABLE[0].name, TABLE[0].len);
    return 0;
}
