#include <stdio.h>

int removeDuplicates(int* nums, int numsSize) {
    if (numsSize <= 1) return numsSize;
    int k = 1;
    for (int i = 1; i < numsSize; i++) {
        if (nums[i] != nums[i - 1]) {
            nums[k++] = nums[i];
        }
    }
    return k;
}

int main() {
    int nums1[] = {1, 1, 2};
    int k1 = removeDuplicates(nums1, 3);
    printf("%d\n", k1);
    for (int i = 0; i < k1; i++) {
        if (i > 0) printf(" ");
        printf("%d", nums1[i]);
    }
    printf("\n");

    int nums2[] = {0, 0, 1, 1, 1, 2, 2, 3, 3, 4};
    int k2 = removeDuplicates(nums2, 10);
    printf("%d\n", k2);
    for (int i = 0; i < k2; i++) {
        if (i > 0) printf(" ");
        printf("%d", nums2[i]);
    }
    printf("\n");

    return 0;
}
