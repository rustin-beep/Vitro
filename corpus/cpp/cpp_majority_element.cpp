#include <stdio.h>
int majorityElement(int* nums, int numsSize) {
    int c = 0, cand = 0;
    for (int i = 0; i < numsSize; i++) {
        if (c == 0) cand = nums[i];
        c = c + (nums[i] == cand ? 1 : -1);
    }
    return cand;
}
int main() {
    int nums[] = {3, 2, 3};
    printf("%d\n", majorityElement(nums, 3));
    return 0;
}
