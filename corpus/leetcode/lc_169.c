#include <stdio.h>

int majorityElement(int* nums, int numsSize) {
    int candidate = nums[0];
    int count = 1;
    for (int i = 1; i < numsSize; i++) {
        if (count == 0) {
            candidate = nums[i];
            count = 1;
        } else if (nums[i] == candidate) {
            count++;
        } else {
            count--;
        }
    }
    return candidate;
}

int main() {
    int nums1[] = {3, 2, 3};
    printf("%d\n", majorityElement(nums1, 3));

    int nums2[] = {2, 2, 1, 1, 1, 2, 2};
    printf("%d\n", majorityElement(nums2, 7));

    return 0;
}
