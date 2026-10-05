#include <stdio.h>
int climbStairs(int n) {
    if (n <= 2) return n;
    int a = 1, b = 2;
    for (int i = 3; i <= n; i++) { int t = a + b; a = b; b = t; }
    return b;
}
int main() {
    printf("%d\n", climbStairs(4));
    return 0;
}
