#include <stdint.h>
#include <stdio.h>

int hammingWeight(uint32_t n) {
    int count = 0;
    while (n != 0) {
        count += n & 1;
        n >>= 1;
    }
    return count;
}

int main(void) {
    printf("%d\n", hammingWeight(11));
    printf("%d\n", hammingWeight(128));
    printf("%d\n", hammingWeight(4294967293u));
    return 0;
}
