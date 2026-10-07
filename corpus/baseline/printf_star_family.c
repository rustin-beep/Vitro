// @category: printf_star
// %*d 星号 printf 族 E2E 锚（批四审阅 P1-2/P2-4 补——wbtest 锚在
// host/typeck 层够不到 dispatch 弹参）：sprintf/snprintf/printf 三臂弹参
//（曾漏改 format_arg_count——sprintf `[    0]` 错值+滞留栈；fprintf 同款
// dispatch 代码路径）+ 负宽度 = 左对齐 |w|（as if "%-*d"）、负精度 =
// 视同省略（C 语义）。scanf %*d 抑制不经语料（cmd/run 直跑 stdin 为
// batch 空输入口径）——由 host_io_wbtest 的 scanf_star_suppression 锚
// + Clang 对拍探针锁定。
#include <stdio.h>
int main() {
    char buf[32];
    sprintf(buf, "[%*d]", 5, 42);
    printf("%s|", buf);
    printf("[%*d][%.*f]", -6, 7, -2, 3.14159);
    snprintf(buf, 10, "{%*d}", 4, 9);
    printf("|%s|\n", buf);
    return 0;
}
