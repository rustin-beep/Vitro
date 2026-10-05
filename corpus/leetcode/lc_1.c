#include <stdio.h>
#include <stdlib.h>

int* twoSum(int* nums, int numsSize, int target, int* returnSize) {
    int* result = (int*)malloc(sizeof(int) * 2);
    *returnSize = 2;
    for (int i = 0; i < numsSize; i++) {
        for (int j = i + 1; j < numsSize; j++) {
            if (nums[i] + nums[j] == target) {
                result[0] = i;
                result[1] = j;
                return result;
            }
        }
    }
    result[0] = -1;
    result[1] = -1;
    return result;
}

int main() {
    int nums1[] = {2, 7, 11, 15};
    int returnSize1 = 0;
    int* r1 = twoSum(nums1, 4, 9, &returnSize1);
    printf("%d %d\n", r1[0], r1[1]);
    free(r1);

    int nums2[] = {3, 2, 4};
    int returnSize2 = 0;
    int* r2 = twoSum(nums2, 3, 6, &returnSize2);
    printf("%d %d\n", r2[0], r2[1]);
    free(r2);

    int nums3[] = {3, 3};
    int returnSize3 = 0;
    int* r3 = twoSum(nums3, 2, 6, &returnSize3);
    printf("%d %d\n", r3[0], r3[1]);
    free(r3);

    return 0;
}
