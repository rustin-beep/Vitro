#include <stdio.h>
#include <stdlib.h>

int cmp(const void* a, const void* b) {
    return (*(int*)a - *(int*)b);
}

int containsDuplicate(int* nums, int numsSize) {
    if (numsSize <= 1) return 0;
    qsort(nums, numsSize, sizeof(int), cmp);
    for (int i = 1; i < numsSize; i++) {
        if (nums[i] == nums[i - 1]) return 1;
    }
    return 0;
}

int main() {
    int nums1[] = {1, 2, 3, 1};
    printf("%d\n", containsDuplicate(nums1, 4));

    int nums2[] = {1, 2, 3, 4};
    printf("%d\n", containsDuplicate(nums2, 4));

    int nums3[] = {1, 1, 1, 3, 3, 4, 3, 2, 4, 2};
    printf("%d\n", containsDuplicate(nums3, 10));

    return 0;
}
