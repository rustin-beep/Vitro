#include <stdio.h>

int rob(int* nums, int numsSize) {
    if (numsSize == 0) {
        return 0;
    }
    if (numsSize == 1) {
        return nums[0];
    }
    int prev2 = nums[0];
    int prev1 = nums[0] > nums[1] ? nums[0] : nums[1];
    for (int i = 2; i < numsSize; i++) {
        int curr = prev1 > prev2 + nums[i] ? prev1 : prev2 + nums[i];
        prev2 = prev1;
        prev1 = curr;
    }
    return prev1;
}

int main() {
    int a1[] = {1, 2, 3, 1};
    printf("%d\n", rob(a1, 4));

    int a2[] = {2, 7, 9, 3, 1};
    printf("%d\n", rob(a2, 5));

    int a3[] = {5};
    printf("%d\n", rob(a3, 1));

    int a4[] = {2, 1, 1, 2};
    printf("%d\n", rob(a4, 4));

    return 0;
}
