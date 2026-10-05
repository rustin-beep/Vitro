#include <stdio.h>

int canJump(int* nums, int numsSize) {
    int maxReach = 0;
    for (int i = 0; i < numsSize; i++) {
        if (i > maxReach) {
            return 0;
        }
        int reach = i + nums[i];
        if (reach > maxReach) {
            maxReach = reach;
        }
        if (maxReach >= numsSize - 1) {
            return 1;
        }
    }
    return 1;
}

int main() {
    int a1[] = {2, 3, 1, 1, 4};
    printf("%d\n", canJump(a1, 5));

    int a2[] = {3, 2, 1, 0, 4};
    printf("%d\n", canJump(a2, 5));

    int a3[] = {0};
    printf("%d\n", canJump(a3, 1));

    int a4[] = {1, 0};
    printf("%d\n", canJump(a4, 2));

    int a5[] = {2, 0, 0};
    printf("%d\n", canJump(a5, 3));

    return 0;
}
