/* #250（2026-10-22 报 / 2026-10-23 修）：深层限定符族降警告——
 * `int**` → `const int**`（嵌套加 const，经典 FAQ 写穿通道）与
 * `const int(*)[3]` decay 给 `int(*)[3]`（数组 element 层剥 const），
 * C11 §6.5.16.1 约束违反但 clang/gcc 默认
 * -Wincompatible-pointer-types-discards-qualifiers 全族仅警告放行；
 * 旧 const_discard_eq 只判顶层 const 位（#80 单层语义），深层族一律
 * E3067 误拒合法 C（语料对拍唯一编译层真回归——外置金样本 2026-10-02
 * 记警告态 → 2026-10-21 轮硬拒态）。qualifier_only_mismatch 递归剥光
 * const 位判同形 → W3053 警告；真不兼容（int\* ← double\*）维持
 * E3067。注：vitro 侧 W3053 警告与 clang 同级，输出面（stdout/exit）
 * 两侧一致。
 * PR #284 审阅 P2-1（2026-10-24）：补 `char *const[]` decay 给
 * `char *const *` 形参的**精确匹配格**——clang 零诊断，vitro 现报
 * W3053 = 已知误报锚（parser 对 `T *const *` 声明符链的 const 层级
 * 归属错，挂在最外层指针位；根因与修复跟踪 issue #285，修复后本格
 * 转「零诊断」并连坐重冻）。警告不进 stdout/exit 对拍面，本例双侧
 * 输出仍一致。 */
#include <stdio.h>
static int T2[2][3] = { { 1, 2, 3 }, { 4, 5, 6 } };
static const int CT[2][3] = { { 9, 8, 7 }, { 6, 5, 4 } };
static int row[3] = { 7, 8, 9 };
static int *rows[2] = { row, row };
static char *const CA[2] = { "x", "y" };
int sum_pp(const int **m, int n) { /* 嵌套加 const 形参 */
    int s = 0;
    for (int i = 0; i < n; i++) s += *m[i];
    return s;
}
int sum_arr(int (*a)[3], int n) { /* 数组指针形参 */
    int s = 0;
    for (int i = 0; i < n; i++) s += a[i][0];
    return s;
}
int const_row_sum(const int (*a)[3], int n) { /* const 加宽安全方向 */
    int s = 0;
    for (int i = 0; i < n; i++) s += a[i][1];
    return s;
}
char first_c(char *const *m) { /* 精确匹配形参（#285 误报形态） */
    return m[0][0];
}
int main(void) {
    printf("%d\n", sum_pp(rows, 2));      /* int** → const int**：嵌套层 */
    printf("%d\n", sum_arr(T2, 2));       /* 匹配基线：零警告 */
    printf("%d\n", const_row_sum(T2, 2)); /* const 加宽：安全方向零警告 */
    printf("%d\n", sum_arr(CT, 2));       /* const int(*)[3] → int(*)[3]：剥 */
    printf("%c\n", first_c(CA));          /* char* const[] → char* const*：#285 已知误报 */
    return 0;
}
