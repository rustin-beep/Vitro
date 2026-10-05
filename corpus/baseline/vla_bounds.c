#include <stdio.h>

int main() {
    int n = 3;
    int a[n];
    for (int i = 0; i < n; i++) {
        a[i] = i * 10;
    }
    printf("%d %d %d\n", a[0], a[1], a[2]);
    return 0;
}
