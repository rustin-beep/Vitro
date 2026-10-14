/* #84（2026-10-13 报 / 2026-10-14 修）：指向 VLA 的行指针
 * （int (*dp)[n+1]）双层病——① 二维 VLA 数组 decay 给行指针被 E3004
 * 误拒（subscript_type 对 VLA 维派生 size=1 vs 声明符侧恒 0 哨兵，
 * type_eq 假阴性）；② 行指针索引报 E0「数组索引步长计算失败：存在
 * 无效维度」（compute_stride 对 VLA 维返 0 哨兵，判定/分派/运行期求值
 * 三处均漏 Pointer 形态）。clang 全变体 ACCEPT（规范 §826 已声明支持
 * 多维 VLA——指针书写法属声明支持面）。修复：subscript_type VLA 维
 * size 归 0 对齐声明侧；gen_index 放行 vla_row_ptr + gen_vla_stride
 * 新增 Pointer 臂（步长 = pointee 全部维度运行期乘积 × 元素尺寸）。
 * 运行期步长验证：dp[1][n2] 跨行读 t[1][n2]=104（行步长 n2+2=6 正确——
 * 步长错则读他值）。 */
#include <stdio.h>
int f(int n1, int n2) {
    int t[n1 + 1][n2 + 2];
    for (int i = 0; i <= n1; i++)
        for (int j = 0; j <= n2; j++) t[i][j] = i * 100 + j;
    int (*dp)[n2 + 2] = t;
    int r = dp[1][n2];
    return r;
}
int main(void) {
    printf("%d\n", f(3, 4));
    return 0;
}
