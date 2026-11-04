// @category: baseline
// 绿锚（#437 即可入库批）：审阅 v2 M21 p06 旗标面好面——+/空格/0/左对齐/# 前缀旗标组合；
// %#x 0 值与 %#08x 排序面属 P7 族分叉，预检分拣取舍。
// 来源：tmp/review_v2_M21/probes/p06_flags.c
#include <stdio.h>
int main(void) {
    printf("[%+d]\n", 42);
    printf("[% d]\n", 42);
    printf("[% d]\n", -42);
    printf("[%05d]\n", -42);
    printf("[%+05d]\n", 42);
    printf("[%#x]\n", 255u);
    printf("[%#X]\n", 255u);
    printf("[%#o]\n", 8u);
    printf("[%#o]\n", 0u);
    printf("[%08.3f]\n", -3.14159);
    printf("[%+.0f]\n", 3.5);
    printf("[%-8.2f|]\n", 3.1);
    return 0;
}
