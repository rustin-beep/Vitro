// @category: baseline
#include <stdio.h>
int main() {
    unsigned int a = 0xFFFFFFFFU;
    a += 2U;
    printf("%u\n", a);
    unsigned int b = 0xFFFFFFFFU;
    b -= 1U;
    printf("%u\n", b);
    unsigned int c = 123456U;
    c *= 98765U;
    printf("%u\n", c);
    return 0;
}
