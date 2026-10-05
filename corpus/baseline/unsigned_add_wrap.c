// @category: baseline
#include <stdio.h>
int main() {
    unsigned int a = 0xFFFFFFFFU;
    unsigned int b = 2U;
    unsigned int c = a + b;
    printf("%u\n", c);
    return 0;
}
