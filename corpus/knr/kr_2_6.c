#include <stdio.h>
unsigned setbits(unsigned x, int p, int n, unsigned y) {
    return (x & ~(~(~0 << n) << (p - n + 1))) |
           ((y & ~(~0 << n)) << (p - n + 1));
}
int main() {
    printf("%u\n", setbits(170, 4, 3, 5));
    return 0;
}
