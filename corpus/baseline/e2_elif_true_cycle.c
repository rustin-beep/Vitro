// @category: baseline
// PR #481 审阅 P1（fail-open 回归锚）：#if 0 … #elif 1 分支激活，真分支
// 内自 include 是真环——gcc/clang 报 #include nested too deeply（stdout 空）；
// Vitro E1015 提前拦截（stdout 空）——双侧编译失败判 match。轻量组栈化前
// 两态版把 #elif 维持跳过 → 真边整段丢弃 → 环检测失效放行（fail-open）。
#include "e2_elif_selfc.h"
int main() { return 0; }
