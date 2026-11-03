// @category: baseline
// 绿锚（#437 即可入库批）：审阅 v2 M21 p07/p08 好面——* 宽度/精度（负宽度左对齐、负精度省略）与
// %.Ns/%Nc 字符串字符宽度精度截断。来源：tmp/review_v2_M21/probes/p07_star.c + p08_bytes.c
#include <stdio.h>
int main(void) {
    printf("[%*d]\n", -5, 42);        // 负宽度=左对齐
    printf("[%.*f]\n", -2, 3.14159);  // 负精度=省略 → 3.141590
    printf("[%*.*f]\n", 9, 2, -1.5);
    printf("[%*d]\n", 3, 12345);      // 宽度小于内容
    printf("[%.3s]\n", "abcdef");
    printf("[%.0s]\n", "abcdef");
    printf("[%8.3s|]\n", "abcdef");
    printf("[%-8.3s|]\n", "abcdef");
    printf("[%3c|]\n", 'A');
    printf("[%-3c|]\n", 'A');
    printf("[%5.2s|]\n", "abcdef");
    return 0;
}
