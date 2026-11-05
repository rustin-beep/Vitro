// @category: baseline
// #432 A3 / M01 c：#if 0 块内的 #include 不是依赖边——四编译器 rc=0
//（#if 0 内内容完全忽略）。Vitro 修复后同 rc=0；修复前 E1015 误报。
#include "e2_if0_selfc.h"
#include <stdio.h>
int main() {
    printf("%d\n", IF0_SELFC);
    return 0;
}
