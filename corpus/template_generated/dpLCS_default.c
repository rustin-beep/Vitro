// @category: baseline
#include <stdio.h>
#include <string.h>

int max(int a, int b) { return a > b ? a : b; }

int lcs(char X[], char Y[]) {
    int m = strlen(X);
    int n = strlen(Y);
    int dp[20][20];
    for (int i = 0; i <= m; i++)
        for (int j = 0; j <= n; j++)
            dp[i][j] = 0;
    for (int i = 1; i <= m; i++) {
        for (int j = 1; j <= n; j++) {
            if (X[i - 1] == Y[j - 1])
                dp[i][j] = dp[i - 1][j - 1] + 1;
            else
                dp[i][j] = max(dp[i - 1][j], dp[i][j - 1]);
        }
    }
    return dp[m][n];
}

int main() {
    char X[] = "ABCBDAB";
    char Y[] = "BDCABA";
    printf("%d\n", lcs(X, Y));
    return 0;
}

