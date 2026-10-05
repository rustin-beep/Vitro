#include <stdio.h>

void moveZeroes(int* nums, int numsSize) {
    int k = 0;
    for (int i = 0; i < numsSize; i++) {
        if (nums[i] != 0) {
            nums[k++] = nums[i];
        }
    }
    for (int i = k; i < numsSize; i++) {
        nums[i] = 0;
    }
}

int main() {
    int nums1[] = {0, 1, 0, 3, 12};
    moveZeroes(nums1, 5);
    for (int i = 0; i < 5; i++) {
        if (i > 0) printf(" ");
        printf("%d", nums1[i]);
    }
    printf("\n");

    int nums2[] = {0};
    moveZeroes(nums2, 1);
    for (int i = 0; i < 1; i++) {
        if (i > 0) printf(" ");
        printf("%d", nums2[i]);
    }
    printf("\n");

    return 0;
}
