#include <stdio.h>

int uniquePaths(int m, int n) {
    int dp[100] = {0};
    for (int i = 0; i < n; i++) {
        dp[i] = 1;
    }
    for (int i = 1; i < m; i++) {
        for (int j = 1; j < n; j++) {
            dp[j] = dp[j] + dp[j - 1];
        }
    }
    return dp[n - 1];
}

int main() {
    printf("%d\n", uniquePaths(3, 7));
    printf("%d\n", uniquePaths(3, 2));
    printf("%d\n", uniquePaths(10, 10));
    printf("%d\n", uniquePaths(1, 1));
    return 0;
}
