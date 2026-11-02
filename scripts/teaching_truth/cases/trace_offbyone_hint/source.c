#include <stdio.h>

/* M31 A-1 红例：经典 i<=5 OffByOne 越界（i 从 0 起）——bounds 历史切片按
   帧数回看 20 帧截得 [4×7, 5×13]，起点误读 4，infer_bounds_category 第二
   判据先于 OffByOne 判据命中 → WrongInit「建议将初始值改为 0」。
   真值：root_cause_hint.category = OffByOne（i 初始值本来就是 0）。 */
int main() {
    int arr[5];
    for (int i = 0; i <= 5; i++) {
        arr[i] = i;
    }
    return 0;
}
