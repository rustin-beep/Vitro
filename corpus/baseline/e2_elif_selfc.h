// PR #481 审阅 P1：#if 0/#elif 1 分支激活——真分支内自 include 是真环
#if 0
#include "never_elif.h"
#elif 1
#include "e2_elif_selfc.h"
#endif
#define ELIF_SELFC 44
