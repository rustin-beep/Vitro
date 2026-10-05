#include <stdio.h>
#include <stdlib.h>

int cmp(const void* a, const void* b) {
    int x = *(int*)a;
    int y = *(int*)b;
    if (x < y) return -1;
    if (x > y) return 1;
    return 0;
}

void threeSum(int* nums, int numsSize) {
    qsort(nums, numsSize, sizeof(int), cmp);
    for (int i = 0; i < numsSize - 2; i++) {
        if (i > 0 && nums[i] == nums[i - 1]) {
            continue;
        }
        int left = i + 1;
        int right = numsSize - 1;
        while (left < right) {
            int sum = nums[i] + nums[left] + nums[right];
            if (sum == 0) {
                printf("%d %d %d\n", nums[i], nums[left], nums[right]);
                while (left < right && nums[left] == nums[left + 1]) {
                    left++;
                }
                while (left < right && nums[right] == nums[right - 1]) {
                    right--;
                }
                left++;
                right--;
            } else if (sum < 0) {
                left++;
            } else {
                right--;
            }
        }
    }
}

int main() {
    int a1[] = {-1, 0, 1, 2, -1, -4};
    threeSum(a1, 6);

    int a2[] = {0, 1, 1};
    threeSum(a2, 3);

    int a3[] = {0, 0, 0};
    threeSum(a3, 3);

    int a4[] = {-2, 0, 0, 2, 2};
    threeSum(a4, 5);

    return 0;
}
