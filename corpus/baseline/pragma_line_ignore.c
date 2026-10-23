/* #212（2026-10-21 报 / 2026-10-23 修）：#pragma/#line 整族降警告跳过
 * ——旧落未知指令分支 E1006 硬拒（#pragma once 中招——学生代码/教材
 * 高频惯用法，题解/模板库广泛使用），且文案「已跳过该行」与 err 终止
 * 编译的实际行为矛盾（说谎文案）。现处置：once 零诊断跳过（重复包含
 * 防护由 resolver 环检测天然承接）；其余 pragma（pack/STDC 族）与
 * #line 降 W1023 警告跳过——语义未实现按默认口径编译。clang 默认对
 * 未知 pragma 零诊断（-Wunknown-pragmas 默认关）、pack(1) 紧缩布局
 * 的 sizeof 与 vitro 默认紧缩布局同值（本例 5）；输出面
 * （stdout/exit）两侧一致。 */
#pragma once
#pragma pack(1)
#line 100
#include <stdio.h>
struct S { char c; int i; };
int main(void) {
    printf("%d\n", sizeof(struct S));
    return 0;
}
