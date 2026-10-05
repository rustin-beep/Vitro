#include <stdio.h>

int minPathSum(int* grid, int m, int n) {
    int dp[200] = {0};
    dp[0] = grid[0];
    for (int i = 1; i < n; i++) {
        dp[i] = dp[i - 1] + grid[i];
    }
    for (int i = 1; i < m; i++) {
        dp[0] = dp[0] + grid[i * n];
        for (int j = 1; j < n; j++) {
            int up = dp[j];
            int left = dp[j - 1];
            dp[j] = (up < left ? up : left) + grid[i * n + j];
        }
    }
    return dp[n - 1];
}

int main() {
    int g1[9] = {1, 3, 1, 1, 5, 1, 4, 2, 1};
    printf("%d\n", minPathSum(g1, 3, 3));
    int g2[6] = {1, 2, 3, 4, 5, 6};
    printf("%d\n", minPathSum(g2, 2, 3));
    int g3[1] = {0};
    printf("%d\n", minPathSum(g3, 1, 1));
    return 0;
}
