#include <stdio.h>

int subarraySum(int* nums, int numsSize, int k) {
    int count = 0;
    for (int start = 0; start < numsSize; start++) {
        int sum = 0;
        for (int end = start; end < numsSize; end++) {
            sum += nums[end];
            if (sum == k) {
                count++;
            }
        }
    }
    return count;
}

int main() {
    int a1[] = {1, 1, 1};
    printf("%d\n", subarraySum(a1, 3, 2));

    int a2[] = {1, 2, 3};
    printf("%d\n", subarraySum(a2, 3, 3));

    int a3[] = {1, -1, 0};
    printf("%d\n", subarraySum(a3, 3, 0));

    return 0;
}
