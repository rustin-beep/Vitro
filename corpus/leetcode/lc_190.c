#include <stdint.h>
#include <stdio.h>

uint32_t reverseBits(uint32_t n) {
    uint32_t res = 0;
    for (int i = 0; i < 32; i++) {
        res = (res << 1) | (n & 1);
        n >>= 1;
    }
    return res;
}

int main(void) {
    printf("%u\n", reverseBits(43261596));
    printf("%u\n", reverseBits(4294967293u));
    return 0;
}
