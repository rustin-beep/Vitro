// @category: baseline
#include <stdio.h>
int main() {
    unsigned int seed = 1;
    seed = seed * 1103515245U + 12345U;
    printf("%u\n", seed);
    return 0;
}
