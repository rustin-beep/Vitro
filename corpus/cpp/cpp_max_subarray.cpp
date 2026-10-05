#include <stdio.h>
int maxSubArray(int* nums, int numsSize) {
    int best = nums[0], cur = nums[0];
    for (int i = 1; i < numsSize; i++) {
        if (cur < 0) cur = nums[i];
        else cur = cur + nums[i];
        if (cur > best) best = cur;
    }
    return best;
}
int main() {
    int nums[] = {-2, 1, -3, 4, -1, 2, 1, -5, 4};
    printf("%d\n", maxSubArray(nums, 9));
    return 0;
}
