#include <stdio.h>

int minCostClimbingStairs(int* cost, int costSize) {
    int dp0 = 0, dp1 = 0;
    for (int i = 2; i <= costSize; i++) {
        int dpi = (dp0 + cost[i - 2] < dp1 + cost[i - 1]) ? dp0 + cost[i - 2] : dp1 + cost[i - 1];
        dp0 = dp1;
        dp1 = dpi;
    }
    return dp1;
}

int main() {
    int cost1[] = {10, 15, 20};
    printf("%d\n", minCostClimbingStairs(cost1, 3));
    int cost2[] = {1, 100, 1, 1, 1, 100, 1, 1, 100, 1};
    printf("%d\n", minCostClimbingStairs(cost2, 10));
    return 0;
}
