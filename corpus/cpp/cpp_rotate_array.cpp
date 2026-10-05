#include <stdio.h>
void reverse(int* a, int l, int r) {
    while (l < r) { int t = a[l]; a[l] = a[r]; a[r] = t; l++; r--; }
}
void rotate(int* nums, int numsSize, int k) {
    k = k % numsSize;
    reverse(nums, 0, numsSize - 1);
    reverse(nums, 0, k - 1);
    reverse(nums, k, numsSize - 1);
}
int main() {
    int nums[] = {1, 2, 3, 4, 5, 6, 7};
    rotate(nums, 7, 3);
    for (int i = 0; i < 7; i++) printf("%d\n", nums[i]);
    return 0;
}
