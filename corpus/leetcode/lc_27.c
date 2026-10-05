#include <stdio.h>

int removeElement(int* nums, int numsSize, int val) {
    int k = 0;
    for (int i = 0; i < numsSize; i++) {
        if (nums[i] != val) {
            nums[k++] = nums[i];
        }
    }
    return k;
}

int main() {
    int nums1[] = {3, 2, 2, 3};
    int k1 = removeElement(nums1, 4, 3);
    printf("%d\n", k1);
    for (int i = 0; i < k1; i++) {
        if (i > 0) printf(" ");
        printf("%d", nums1[i]);
    }
    printf("\n");

    int nums2[] = {0, 1, 2, 2, 3, 0, 4, 2};
    int k2 = removeElement(nums2, 8, 2);
    printf("%d\n", k2);
    for (int i = 0; i < k2; i++) {
        if (i > 0) printf(" ");
        printf("%d", nums2[i]);
    }
    printf("\n");

    return 0;
}
