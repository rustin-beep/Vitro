// @category: baseline
// E2：守卫自 include（stb 模式）。#ifndef 守卫令二次展开为空，GCC/Clang 均编译通过；Vitro 修复前静态环检测把「回到起点」一律判环误报 E1015，
// 修复后环上任一守卫即 include-once 终点。stdout 空，main 返回 7。
#include "e2_guarded_self_include.h"
int main() {
    return guarded_value();
}
