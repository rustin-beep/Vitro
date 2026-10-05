#include <stdio.h>

int maxSubArray(int* nums, int numsSize) {
    int max_sum = nums[0];
    int current_sum = nums[0];
    for (int i = 1; i < numsSize; i++) {
        if (current_sum < 0) {
            current_sum = nums[i];
        } else {
            current_sum += nums[i];
        }
        if (current_sum > max_sum) {
            max_sum = current_sum;
        }
    }
    return max_sum;
}

int main() {
    int a1[] = {-2, 1, -3, 4, -1, 2, 1, -5, 4};
    printf("%d\n", maxSubArray(a1, 9));

    int a2[] = {1};
    printf("%d\n", maxSubArray(a2, 1));

    int a3[] = {5, 4, -1, 7, 8};
    printf("%d\n", maxSubArray(a3, 5));

    return 0;
}
