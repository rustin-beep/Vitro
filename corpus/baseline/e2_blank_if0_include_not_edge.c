// @category: baseline
// PR #481 审阅 P2："#  if 0"（# 后空白）块内的 #include 不是依赖边——
// 四编译器 rc=0。Vitro 修复后同 rc=0；修复前 directive_name_of 未归一
// 漏检 → E1015 依赖环误报。
#include "e2_blank_if0_selfc.h"
#include <stdio.h>
int main() {
    printf("%d\n", BLANK_IF0_SELFC);
    return 0;
}
