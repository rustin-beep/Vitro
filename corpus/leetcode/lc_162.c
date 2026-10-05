#include <stdio.h>

int findPeakElement(int* nums, int numsSize) {
    int left = 0;
    int right = numsSize - 1;
    while (left < right) {
        int mid = left + (right - left) / 2;
        if (nums[mid] > nums[mid + 1]) {
            right = mid;
        } else {
            left = mid + 1;
        }
    }
    return left;
}

int main() {
    int a1[] = {1, 2, 3, 1};
    printf("%d\n", findPeakElement(a1, 4));

    int a2[] = {1, 2, 1, 3, 5, 6, 4};
    printf("%d\n", findPeakElement(a2, 7));

    return 0;
}
