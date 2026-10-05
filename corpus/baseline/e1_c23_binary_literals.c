// @category: baseline
// C23（E1）：0b 二进制字面量
#include <stdio.h>
int main() {
    int a = 0b1010;
    int b = 0B11111111;
    int c = 0b1010 + 0x10;
    unsigned u = 0b100000000;
    printf("%d %d %d %u\n", a, b, c, u);
    return 0;
}
