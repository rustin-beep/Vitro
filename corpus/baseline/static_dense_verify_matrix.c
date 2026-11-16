#include <stdio.h>

// @category: 静态区容量带（#271）——2×128KB double 稠密验证矩阵（「稀疏乘
// 稀疏易错，先用稠密对照」的标准教学手法）。旧 GLOBAL_REGION_LIMIT=64KB
// 整体拒绝（clang/gcc 正常跑）；#271 放宽至 320KB 后的行为锚。首尾写读验证
// 大数组两端真实可用（不被懒分配截断）。

static double da[128 * 128];
static double db[128 * 128];
static int seed = 7;

int main() {
    da[0] = seed;
    da[16383] = seed * 2;
    db[0] = da[0] + 1;
    db[16383] = da[16383] + 1;
    printf("%.1f %.1f %.1f %.1f\n", da[0], db[0], da[16383], db[16383]);
    return 0;
}
