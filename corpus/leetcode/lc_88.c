#include <stdio.h>

void merge(int* nums1, int nums1Size, int m, int* nums2, int nums2Size, int n) {
    int i = m - 1;
    int j = n - 1;
    int k = m + n - 1;
    while (i >= 0 && j >= 0) {
        if (nums1[i] > nums2[j]) {
            nums1[k--] = nums1[i--];
        } else {
            nums1[k--] = nums2[j--];
        }
    }
    while (j >= 0) {
        nums1[k--] = nums2[j--];
    }
}

int main() {
    int nums1[] = {1, 2, 3, 0, 0, 0};
    int nums2[] = {2, 5, 6};
    merge(nums1, 6, 3, nums2, 3, 3);
    for (int i = 0; i < 6; i++) {
        if (i > 0) printf(" ");
        printf("%d", nums1[i]);
    }
    printf("\n");

    int nums3[] = {1};
    int nums4[] = {};
    merge(nums3, 1, 1, nums4, 0, 0);
    for (int i = 0; i < 1; i++) {
        if (i > 0) printf(" ");
        printf("%d", nums3[i]);
    }
    printf("\n");

    return 0;
}
