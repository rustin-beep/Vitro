// @category: baseline
// 绿锚（#437 修复后入库批）：速查表 G8/G9/G10 行——NaN 输出族大小写统一：%f NaN 大写（Rust {:?}
// 拼法照搬，应小写 nan）、%e/%f 大小写互不一致、%F 无执行臂字母原样。B4 批（#427，2026-11-03）
// 修复后翻面入桶；±inf 好面由 m21_printf_inf_nan.c 锁（其头注明「NaN 大小写族属分叉面……修复后
// 入库批覆盖」即本文件）。D4 注：glibc 0.0/0.0 运行时常量折叠给 -nan（符号位差，非翻面目标）。
// 来源：tmp/review_v2_M21 p03 / M20 A-12 / V1#33。
#include <stdio.h>
int main(void) {
    printf("%f|%e|%g\n", 0.0/0.0, 0.0/0.0, 0.0/0.0);   // clang: nan|nan|nan
    printf("%F\n", 0.0/0.0);                            // clang: NAN（大写）
    return 0;
}
