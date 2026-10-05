#include <stdio.h>

void reverse(int* nums, int start, int end) {
    while (start < end) {
        int tmp = nums[start];
        nums[start] = nums[end];
        nums[end] = tmp;
        start++;
        end--;
    }
}

void rotate(int* nums, int numsSize, int k) {
    k = k % numsSize;
    if (k == 0) return;
    reverse(nums, 0, numsSize - 1);
    reverse(nums, 0, k - 1);
    reverse(nums, k, numsSize - 1);
}

int main() {
    int nums1[] = {1, 2, 3, 4, 5, 6, 7};
    rotate(nums1, 7, 3);
    for (int i = 0; i < 7; i++) {
        if (i > 0) printf(" ");
        printf("%d", nums1[i]);
    }
    printf("\n");

    int nums2[] = {-1, -100, 3, 99};
    rotate(nums2, 4, 2);
    for (int i = 0; i < 4; i++) {
        if (i > 0) printf(" ");
        printf("%d", nums2[i]);
    }
    printf("\n");

    return 0;
}
