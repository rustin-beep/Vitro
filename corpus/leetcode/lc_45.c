#include <stdio.h>

int jump(int* nums, int numsSize) {
    if (numsSize <= 1) {
        return 0;
    }
    int jumps = 0;
    int current_end = 0;
    int farthest = 0;
    for (int i = 0; i < numsSize - 1; i++) {
        if (i + nums[i] > farthest) {
            farthest = i + nums[i];
        }
        if (i == current_end) {
            jumps++;
            current_end = farthest;
        }
    }
    return jumps;
}

int main() {
    int a1[] = {2, 3, 1, 1, 4};
    printf("%d\n", jump(a1, 5));

    int a2[] = {2, 3, 0, 1, 4};
    printf("%d\n", jump(a2, 5));

    return 0;
}
