#include <stdio.h>

int josephus(int n, int m) {
    int r = 0;
    for (int i = 2; i <= n; i++) {
        r = (r + m) % i;
    }
    return r;
}

int main() {
    printf("n=5 m=3 最后幸存者编号: %d\n", josephus(5, 3));
    printf("n=10 m=2 最后幸存者编号: %d\n", josephus(10, 2));
    return 0;
}
