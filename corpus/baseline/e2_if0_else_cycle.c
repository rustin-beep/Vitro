// @category: baseline
// #432 A2/A3 防过剥守卫：#else 分支激活后的自 include 是真环——gcc/clang
// 报嵌套过深 fatal（stdout 空）；Vitro E1015 提前拦截（stdout 空）——
// 双侧编译失败判 match。轻量剥离若整块跳过 #if 0…#endif 会漏此真环。
#include "e2_if0else_selfc.h"
int main() { return 0; }
