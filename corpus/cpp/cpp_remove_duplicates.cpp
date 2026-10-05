#include <stdio.h>
int removeDuplicates(int* nums, int numsSize) {
    if (numsSize == 0) return 0;
    int k = 1;
    for (int i = 1; i < numsSize; i++) if (nums[i] != nums[k - 1]) nums[k++] = nums[i];
    return k;
}
int main() {
    int nums[] = {0, 0, 1, 1, 2, 2, 3, 3, 4};
    int k = removeDuplicates(nums, 9);
    printf("%d\n", k);
    for (int i = 0; i < k; i++) printf("%d\n", nums[i]);
    return 0;
}
