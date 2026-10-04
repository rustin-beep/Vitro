#include <stdio.h>

int isPrime(int n) {
    if (n <= 1) return 0;
    for (int i = 2; i * i <= n; i++) {
        if (n % i == 0) return 0;
    }
    return 1;
}

int main() {
    int count = 0;
    for (int n = 2; n <= 30; n++) {
        if (isPrime(n)) {
            printf("%d ", n);
            count++;
        }
    }
    printf("\n共 %d 个素数\n", count);
    return 0;
}
