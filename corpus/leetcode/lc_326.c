#include <stdio.h>

int isPowerOfThree(int n) {
    if (n <= 0) return 0;
    while (n % 3 == 0) n /= 3;
    return n == 1;
}

int main(void) {
    printf("%d\n", isPowerOfThree(27));
    printf("%d\n", isPowerOfThree(0));
    printf("%d\n", isPowerOfThree(-1));
    printf("%d\n", isPowerOfThree(9));
    printf("%d\n", isPowerOfThree(45));
    return 0;
}
