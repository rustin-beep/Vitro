// #432 A3：#if 0 块内的 #include 不是依赖边（#if 0 注释掉代码块是 C 工程
// 最常见形态）
#if 0
#include "e2_if0_selfc.h"
#endif
#define IF0_SELFC 42
