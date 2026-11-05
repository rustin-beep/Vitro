// #432 A2/A3 防过剥守卫：#if 0 … #else 分支激活——else 内自 include 是
// 真边（gcc/clang 报 #include nested too deeply 拦截）
#if 0
#include "never_exists.h"
#else
#include "e2_if0else_selfc.h"
#endif
#define IF0ELSE_SELFC 43
