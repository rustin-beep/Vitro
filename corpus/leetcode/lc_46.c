#include <stdio.h>

int used[6];
int perm[6];
int g_nums[6];
int g_numsSize;

void backtrack(int depth) {
    if (depth == g_numsSize) {
        for (int i = 0; i < g_numsSize; i++) {
            printf("%d", perm[i]);
            if (i + 1 < g_numsSize) {
                printf(" ");
            }
        }
        printf("\n");
        return;
    }
    for (int i = 0; i < g_numsSize; i++) {
        if (used[i]) {
            continue;
        }
        used[i] = 1;
        perm[depth] = g_nums[i];
        backtrack(depth + 1);
        used[i] = 0;
    }
}

void permute(int* nums, int numsSize) {
    g_numsSize = numsSize;
    for (int i = 0; i < numsSize; i++) {
        g_nums[i] = nums[i];
        used[i] = 0;
    }
    backtrack(0);
}

int main() {
    int n1[] = {1, 2, 3};
    permute(n1, 3);

    int n2[] = {0, 1};
    permute(n2, 2);

    int n3[] = {1};
    permute(n3, 1);

    return 0;
}
