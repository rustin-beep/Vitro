// @category: baseline
#include <stdio.h>

int min(int a, int b) { return a < b ? a : b; }

int coinChange(int coins[], int coinCount, int amount) {
    int dp[101];
    for (int i = 0; i <= amount; i++) dp[i] = 100000;
    dp[0] = 0;
    for (int i = 0; i < coinCount; i++) {
        for (int j = coins[i]; j <= amount; j++) {
            dp[j] = min(dp[j], dp[j - coins[i]] + 1);
        }
    }
    if (dp[amount] == 100000) return -1;
    return dp[amount];
}

int main() {
    int coins[] = {1, 2, 5};
    int amount = 11;
    int result = coinChange(coins, 3, amount);
    printf("%d\n", result);
    return 0;
}

