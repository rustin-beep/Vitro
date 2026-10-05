// @category: baseline
#include <stdio.h>
#define MAXN 50

void sieve(int n) {
    int isPrime[MAXN];
    for (int i = 0; i <= n; i++) isPrime[i] = 1;
    isPrime[0] = isPrime[1] = 0;
    for (int i = 2; i * i <= n; i++) {
        if (isPrime[i]) {
            for (int j = i * i; j <= n; j += i)
                isPrime[j] = 0;
        }
    }
    for (int i = 2; i <= n; i++)
        if (isPrime[i]) printf("%d ", i);
    printf("\n");
}

int main() {
    int n = 30;
    sieve(n);
    return 0;
}

