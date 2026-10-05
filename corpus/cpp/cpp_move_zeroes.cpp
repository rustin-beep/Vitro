#include <stdio.h>
void moveZeroes(int* nums, int numsSize) {
    int k = 0;
    for (int i = 0; i < numsSize; i++) if (nums[i] != 0) nums[k++] = nums[i];
    for (int i = k; i < numsSize; i++) nums[i] = 0;
}
int main() {
    int nums[] = {0, 1, 0, 3, 12};
    moveZeroes(nums, 5);
    for (int i = 0; i < 5; i++) printf("%d\n", nums[i]);
    return 0;
}
