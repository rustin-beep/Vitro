#include <stdio.h>
int main() {
    int n = 4;
    printf("%d\n", sizeof(int[n]));
    printf("%d\n", sizeof(int[n][3]));
    int m = 2;
    printf("%d\n", sizeof(int[n][m]));
    return 0;
}
