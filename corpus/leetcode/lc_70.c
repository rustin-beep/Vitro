#include <stdio.h>

int climbStairs(int n) {
    if (n <= 2) return n;
    int prev2 = 1;
    int prev1 = 2;
    int curr = 0;
    for (int i = 3; i <= n; i++) {
        curr = prev1 + prev2;
        prev2 = prev1;
        prev1 = curr;
    }
    return curr;
}

int main() {
    printf("%d\n", climbStairs(2));
    printf("%d\n", climbStairs(3));
    printf("%d\n", climbStairs(4));
    printf("%d\n", climbStairs(10));
    return 0;
}
