#include <stdio.h>

int coinChange(int* coins, int coinsSize, int amount) {
    int dp[10001];
    for (int i = 0; i <= amount; i++) {
        dp[i] = 10001;
    }
    dp[0] = 0;
    for (int i = 1; i <= amount; i++) {
        for (int j = 0; j < coinsSize; j++) {
            if (coins[j] <= i && dp[i - coins[j]] + 1 < dp[i]) {
                dp[i] = dp[i - coins[j]] + 1;
            }
        }
    }
    return dp[amount] == 10001 ? -1 : dp[amount];
}

int main() {
    int c1[] = {1, 2, 5};
    printf("%d\n", coinChange(c1, 3, 11));

    int c2[] = {2};
    printf("%d\n", coinChange(c2, 1, 3));

    int c3[] = {1};
    printf("%d\n", coinChange(c3, 1, 0));

    int c4[] = {186, 419, 83, 408};
    printf("%d\n", coinChange(c4, 4, 6249));

    return 0;
}
