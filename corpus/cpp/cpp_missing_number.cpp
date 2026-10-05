#include <stdio.h>
int missingNumber(int* nums, int numsSize) {
    int r = numsSize;
    for (int i = 0; i < numsSize; i++) r = r + i - nums[i];
    return r;
}
int main() {
    int nums[] = {3, 0, 1};
    printf("%d\n", missingNumber(nums, 3));
    return 0;
}
