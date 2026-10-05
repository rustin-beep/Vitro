/* 下游需求 A1 回归：**流耗尽必须返回 EOF，而不是永久挂起**。
 *
 * 修复前：scanf 在"首个转换符之前流已无可用内容"时无条件进入
 * `waiting_input`，批量模式下无人再喂输入 → 引擎挂死（下游实际卡死）。
 * 修复后：`InputMode::Batch` 下该分支直接 push -1（EOF），
 * `while (scanf(...) != EOF)` 这类标准读入循环得以正常退出。
 *
 * 注意：本用例不写 `@category:`，走 Shadow 默认的 baseline 分类——
 * 一旦回归会判 output_gap（非预期差异），门禁非零退出。
 */
#include <stdio.h>

int main() {
    int n = 0;
    int sum = 0;
    int cnt = 0;
    int r = 0;
    while ((r = scanf("%d", &n)) != EOF) {
        sum += n;
        cnt++;
    }
    printf("cnt=%d sum=%d last_r=%d\n", cnt, sum, r);
    return 0;
}
