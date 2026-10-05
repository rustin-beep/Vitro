#include <stdio.h>
#include <stdlib.h>

int* productExceptSelf(int* nums, int numsSize, int* returnSize) {
    int* result = (int*)malloc(sizeof(int) * numsSize);
    *returnSize = numsSize;
    result[0] = 1;
    for (int i = 1; i < numsSize; i++) {
        result[i] = result[i - 1] * nums[i - 1];
    }
    int suffix = 1;
    for (int i = numsSize - 1; i >= 0; i--) {
        result[i] *= suffix;
        suffix *= nums[i];
    }
    return result;
}

int main() {
    int nums1[] = {1, 2, 3, 4};
    int returnSize1 = 0;
    int* r1 = productExceptSelf(nums1, 4, &returnSize1);
    for (int i = 0; i < returnSize1; i++) {
        if (i > 0) printf(" ");
        printf("%d", r1[i]);
    }
    printf("\n");
    free(r1);

    int nums2[] = {-1, 1, 0, -3, 3};
    int returnSize2 = 0;
    int* r2 = productExceptSelf(nums2, 5, &returnSize2);
    for (int i = 0; i < returnSize2; i++) {
        if (i > 0) printf(" ");
        printf("%d", r2[i]);
    }
    printf("\n");
    free(r2);

    return 0;
}
