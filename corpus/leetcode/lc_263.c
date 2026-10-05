#include <stdio.h>
#include <stdio.h>

int isUgly(int n) {
    if (n <= 0) return 0;
    while (n % 2 == 0) n /= 2;
    while (n % 3 == 0) n /= 3;
    while (n % 5 == 0) n /= 5;
    return n == 1;
}

int main(void) {
    printf("%d\n", isUgly(6));
    printf("%d\n", isUgly(8));
    printf("%d\n", isUgly(14));
    printf("%d\n", isUgly(1));
    return 0;
}
