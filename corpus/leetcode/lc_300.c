#include <stdio.h>

int lengthOfLIS(int* nums, int numsSize) {
    if (numsSize == 0) {
        return 0;
    }
    int dp[100];
    int max_len = 1;
    for (int i = 0; i < numsSize; i++) {
        dp[i] = 1;
        for (int j = 0; j < i; j++) {
            if (nums[j] < nums[i] && dp[j] + 1 > dp[i]) {
                dp[i] = dp[j] + 1;
            }
        }
        if (dp[i] > max_len) {
            max_len = dp[i];
        }
    }
    return max_len;
}

int main() {
    int a1[] = {10, 9, 2, 5, 3, 7, 101, 18};
    printf("%d\n", lengthOfLIS(a1, 8));

    int a2[] = {0, 1, 0, 3, 2, 3};
    printf("%d\n", lengthOfLIS(a2, 6));

    int a3[] = {7, 7, 7, 7, 7, 7, 7};
    printf("%d\n", lengthOfLIS(a3, 7));

    return 0;
}
