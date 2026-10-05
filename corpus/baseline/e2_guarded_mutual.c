// @category: baseline
// E2：守卫互包含环（a 有守卫、b 无）。C 语义下环的有序展开中首个带守卫文件二次展开为空、递归断链，不会爆深；
// Vitro 修复前从 b 出发的静态检测误报 E1015，修复后环上任一守卫即终点。stdout 空，main 返回 8。
#include "e2_guarded_mutual_a.h"
int main() {
    return gm_a_value + gm_b_value;
}
