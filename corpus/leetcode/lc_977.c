#include <stdio.h>

int* sortedSquares(int* nums, int numsSize, int* returnSize) {
    static int result[10000];
    *returnSize = numsSize;
    int left = 0, right = numsSize - 1;
    int pos = numsSize - 1;
    while (left <= right) {
        int lv = nums[left];
        int rv = nums[right];
        if (lv * lv > rv * rv) {
            result[pos--] = lv * lv;
            left++;
        } else {
            result[pos--] = rv * rv;
            right--;
        }
    }
    return result;
}

int main() {
    int nums[] = {-4, -1, 0, 3, 10};
    int size = 0;
    int* r = sortedSquares(nums, 5, &size);
    for (int i = 0; i < size; i++) printf("%d\n", r[i]);
    return 0;
}
