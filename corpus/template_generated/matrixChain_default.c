// @category: baseline
#include <stdio.h>

int matrixChainOrder(int p[], int n) {
    int dp[10][10];
    for (int i = 0; i < n; i++)
        for (int j = 0; j < n; j++)
            dp[i][j] = 0;
    for (int len = 2; len < n; len++) {
        for (int i = 1; i < n - len + 1; i++) {
            int j = i + len - 1;
            dp[i][j] = 100000000;
            for (int k = i; k < j; k++) {
                int cost = dp[i][k] + dp[k + 1][j] + p[i - 1] * p[k] * p[j];
                if (cost < dp[i][j]) dp[i][j] = cost;
            }
        }
    }
    return dp[1][n - 1];
}

int main() {
    int p[] = {30, 35, 15, 5, 10, 20, 25};
    int n = 6;
    printf("%d\n", matrixChainOrder(p, n + 1));
    return 0;
}

