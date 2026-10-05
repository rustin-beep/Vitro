#include <stdio.h>
int singleNumber(int* nums, int numsSize) {
    int r = 0;
    for (int i = 0; i < numsSize; i++) r = r ^ nums[i];
    return r;
}
int main() {
    int nums[] = {4, 1, 2, 1, 2};
    printf("%d\n", singleNumber(nums, 5));
    return 0;
}
