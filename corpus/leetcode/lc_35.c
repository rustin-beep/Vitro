#include <stdio.h>

int searchInsert(int* nums, int numsSize, int target) {
    int left = 0, right = numsSize - 1;
    while (left <= right) {
        int mid = left + (right - left) / 2;
        if (nums[mid] == target) return mid;
        if (nums[mid] < target) left = mid + 1;
        else right = mid - 1;
    }
    return left;
}

int main() {
    int nums[] = {1, 3, 5, 6};
    printf("%d\n", searchInsert(nums, 4, 5));
    printf("%d\n", searchInsert(nums, 4, 2));
    printf("%d\n", searchInsert(nums, 4, 7));
    return 0;
}
