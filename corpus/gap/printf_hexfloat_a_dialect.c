// @category: arch_diff_bug
// 实现定义域方言锚（#437 修复后入库批，gap 桶）：速查表 P3/P4 行——%a/%A 十六进制浮点
// 十六进制小数位数属实现定义域（C11 7.21.6.1p8 仅定格式框架）：UCRT 13 位全印
// （0x1.8000000000000p+0）、glibc 最短（0x1.8p+0），真值间自分歧。Vitro（B4 批 #427 修复
// 补执行臂）择 glibc 最短形态——与 Win clang 直拍必然 diff，known_direct 登记（digest 锁
// UCRT 侧输出，跨 clang 版本形态漂移时红）。%F 行（P2）已修一致为对照。来源：
// tmp/review_v2_M20 A-2 / M21 A3 / V1#33。
#include <stdio.h>
int main(void) {
    printf("A[%F|%d]\n", 3.5, 7);        // clang: A[3.500000|7]（一致对照）
    printf("B[%a|%d]\n", 1.5, 42);       // UCRT: 0x1.8000000000000p+0 | glibc·vitro: 0x1.8p+0
    printf("C[%A|%d]\n", 1.5, 44);       // UCRT: 0X1.8000000000000P+0 | glibc·vitro: 0X1.8P+0
    return 0;
}
