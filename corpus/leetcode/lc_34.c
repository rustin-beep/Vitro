#include <stdio.h>

int find_first(int* nums, int numsSize, int target) {
    int left = 0;
    int right = numsSize - 1;
    int ans = -1;
    while (left <= right) {
        int mid = left + (right - left) / 2;
        if (nums[mid] == target) {
            ans = mid;
            right = mid - 1;
        } else if (nums[mid] < target) {
            left = mid + 1;
        } else {
            right = mid - 1;
        }
    }
    return ans;
}

int find_last(int* nums, int numsSize, int target) {
    int left = 0;
    int right = numsSize - 1;
    int ans = -1;
    while (left <= right) {
        int mid = left + (right - left) / 2;
        if (nums[mid] == target) {
            ans = mid;
            left = mid + 1;
        } else if (nums[mid] < target) {
            left = mid + 1;
        } else {
            right = mid - 1;
        }
    }
    return ans;
}

void searchRange(int* nums, int numsSize, int target) {
    int first = find_first(nums, numsSize, target);
    int last = find_last(nums, numsSize, target);
    printf("%d %d\n", first, last);
}

int main() {
    int nums1[] = {5, 7, 7, 8, 8, 10};
    searchRange(nums1, 6, 8);
    searchRange(nums1, 6, 6);

    int nums2[] = {};
    searchRange(nums2, 0, 0);

    int nums3[] = {1};
    searchRange(nums3, 1, 1);

    int nums4[] = {2, 2};
    searchRange(nums4, 2, 2);

    return 0;
}
