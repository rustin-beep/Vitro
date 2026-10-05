#ifndef E2_GUARDED_SELF_INCLUDE_H
#define E2_GUARDED_SELF_INCLUDE_H
int guarded_value(void) { return 7; }
/* stb 标准模式：守卫下自 include——二次展开为空（GCC/Clang 均支持） */
#include "e2_guarded_self_include.h"
#endif
