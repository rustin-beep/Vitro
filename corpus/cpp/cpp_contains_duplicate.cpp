#include <stdio.h>
#include <stdlib.h>
int cmp(const void* a, const void* b) { return *(int*)a - *(int*)b; }
int containsDuplicate(int* nums, int numsSize) {
    qsort(nums, numsSize, sizeof(int), cmp);
    for (int i = 1; i < numsSize; i++) if (nums[i] == nums[i-1]) return 1;
    return 0;
}
int main() {
    int nums[] = {1, 2, 3, 4};
    printf("%d\n", containsDuplicate(nums, 4));
    return 0;
}
