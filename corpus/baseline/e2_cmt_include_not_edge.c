// @category: baseline
// #432 A2 / M01 b2：块注释内的 #include 不是依赖边——Win/WSL gcc+clang
// 四编译器 rc=0 正常编译。Vitro 修复后同 rc=0；修复前 custom_includes_of
// 文本级扫描把注释内 include 当真边 → E1015 依赖环误报拒编译。
#include "e2_cmt_selfc.h"
#include <stdio.h>
int main() {
    printf("%d\n", CMT_SELFC);
    return 0;
}
