// @category: baseline
#include <stdio.h>
#define N 10

int main() {
    int alive[N];
    for (int i = 0; i < N; i++) alive[i] = 1;
    int count = 0, i = 0, remain = N;
    int m = 3;
    while (remain > 0) {
        if (alive[i]) {
            count++;
            if (count == m) {
                alive[i] = 0;
                printf("%d ", i);
                count = 0;
                remain--;
            }
        }
        i = (i + 1) % N;
    }
    printf("\n");
    return 0;
}

