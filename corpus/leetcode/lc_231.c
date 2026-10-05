#include <stdio.h>
#include <stdio.h>

int isPowerOfTwo(int n) {
    return n > 0 && (n & (n - 1)) == 0;
}

int main(void) {
    printf("%d\n", isPowerOfTwo(1));
    printf("%d\n", isPowerOfTwo(16));
    printf("%d\n", isPowerOfTwo(3));
    printf("%d\n", isPowerOfTwo(-16));
    return 0;
}
