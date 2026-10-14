/* #80（2026-10-13 报 / 2026-10-14 修）：const 限定符**丢弃方向**降警告
 * ——`const int[3]` decay 给 `int*`（赋值位旧 E3044 / 初始化位旧 E3004）
 * 与 `const int*` 给 `int*`（pointee 丢弃旧 E3067），clang/gcc 默认
 * -Wincompatible-pointer-types-discards-qualifiers 仅警告放行，旧一律
 * error 误拒合法 C。const_discard_eq 单层判等（unqualified 相等只差
 * const 位）→ W3053 警告；真不兼容（int* ← double*）维持 E3067。
 * 注：vitro 侧 W3053 警告与 clang 同级，输出面（stdout/exit）两侧一致。 */
#include <stdio.h>
static const int T[3] = {1, 2, 3};
static const int TAB[] = {4, 5, 6};
const int *q = 0;
int main(void) {
    int *p1 = T;   /* 初始化位：const int[3] → int* */
    int *p2;
    p2 = TAB;      /* 赋值位：const int[]（省略尺寸）→ int* */
    int *p3 = q;   /* pointee 丢弃：const int* → int* */
    printf("%d %d %d\n", p1[0], p2[0], p3 == 0);
    return 0;
}
