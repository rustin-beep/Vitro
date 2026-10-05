#include <stdio.h>

int maxProduct(int* nums, int numsSize) {
    int max_ending = nums[0];
    int min_ending = nums[0];
    int result = nums[0];
    for (int i = 1; i < numsSize; i++) {
        int x = nums[i];
        if (x < 0) {
            int tmp = max_ending;
            max_ending = min_ending;
            min_ending = tmp;
        }
        max_ending = x > max_ending * x ? x : max_ending * x;
        min_ending = x < min_ending * x ? x : min_ending * x;
        if (max_ending > result) {
            result = max_ending;
        }
    }
    return result;
}

int main() {
    int a1[] = {2, 3, -2, 4};
    printf("%d\n", maxProduct(a1, 4));

    int a2[] = {-2, 0, -1};
    printf("%d\n", maxProduct(a2, 3));

    int a3[] = {-2};
    printf("%d\n", maxProduct(a3, 1));

    int a4[] = {0, 2};
    printf("%d\n", maxProduct(a4, 2));

    return 0;
}
