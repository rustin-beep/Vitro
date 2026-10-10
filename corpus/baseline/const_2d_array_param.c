/* #63（2026-10-10）：const 二维数组形参——`const int g[9][9]` 退化
 * `const int(*)[9]`（const 在 pointee 数组 element 层）收 `int(*)[9]` 实参，
 * 数组限定符传导元素（C11 §6.7.3/§6.7.6.2）合法；病 3 单层 strip 够不着
 * 该形态。反向（形参非 const 收 const 数组——剥 const 写穿）不在本例。
 */
#include <stdio.h>
static void fill_nonconst(int g[9][9]) { g[0][0] = 7; }
static int read_const(const int g[9][9], int r, int c) { return g[r][c]; }
int main(void) {
    int grid[9][9] = {{0}};
    fill_nonconst(grid);
    printf("%d %d\n", grid[0][0], read_const(grid, 0, 1));
    return 0;
}
