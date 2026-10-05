#include <stdio.h>

int missingNumber(int* nums, int numsSize) {
    int expected = numsSize * (numsSize + 1) / 2;
    int actual = 0;
    for (int i = 0; i < numsSize; i++) {
        actual += nums[i];
    }
    return expected - actual;
}

int main() {
    int nums1[] = {3, 0, 1};
    printf("%d\n", missingNumber(nums1, 3));

    int nums2[] = {0, 1};
    printf("%d\n", missingNumber(nums2, 2));

    int nums3[] = {9, 6, 4, 2, 3, 5, 7, 0, 1};
    printf("%d\n", missingNumber(nums3, 9));

    return 0;
}
