// @category: baseline
#include <stdio.h>

int max(int a, int b) { return a > b ? a : b; }

int lis(int arr[], int n) {
    int dp[20];
    for (int i = 0; i < n; i++) dp[i] = 1;
    int result = 1;
    for (int i = 1; i < n; i++) {
        for (int j = 0; j < i; j++) {
            if (arr[j] < arr[i])
                dp[i] = max(dp[i], dp[j] + 1);
        }
        result = max(result, dp[i]);
    }
    return result;
}

int main() {
    int arr[] = {10, 9, 2, 5, 3, 7, 101, 18};
    int n = 8;
    printf("%d\n", lis(arr, n));
    return 0;
}

