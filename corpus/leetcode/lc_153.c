#include <stdio.h>

int findMin(int* nums, int numsSize) {
    int left = 0;
    int right = numsSize - 1;
    while (left < right) {
        int mid = left + (right - left) / 2;
        if (nums[mid] > nums[right]) {
            left = mid + 1;
        } else {
            right = mid;
        }
    }
    return nums[left];
}

int main() {
    int a1[] = {3, 4, 5, 1, 2};
    printf("%d\n", findMin(a1, 5));

    int a2[] = {4, 5, 6, 7, 0, 1, 2};
    printf("%d\n", findMin(a2, 7));

    int a3[] = {11, 13, 15, 17};
    printf("%d\n", findMin(a3, 4));

    int a4[] = {2, 1};
    printf("%d\n", findMin(a4, 2));

    return 0;
}
