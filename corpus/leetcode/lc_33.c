#include <stdio.h>

int search(int* nums, int numsSize, int target) {
    int left = 0;
    int right = numsSize - 1;
    while (left <= right) {
        int mid = left + (right - left) / 2;
        if (nums[mid] == target) {
            return mid;
        }
        if (nums[left] <= nums[mid]) {
            if (target >= nums[left] && target < nums[mid]) {
                right = mid - 1;
            } else {
                left = mid + 1;
            }
        } else {
            if (target > nums[mid] && target <= nums[right]) {
                left = mid + 1;
            } else {
                right = mid - 1;
            }
        }
    }
    return -1;
}

int main() {
    int nums1[] = {4, 5, 6, 7, 0, 1, 2};
    printf("%d\n", search(nums1, 7, 0));
    printf("%d\n", search(nums1, 7, 3));
    int nums2[] = {1};
    printf("%d\n", search(nums2, 1, 0));
    int nums3[] = {1, 3};
    printf("%d\n", search(nums3, 2, 3));
    return 0;
}
