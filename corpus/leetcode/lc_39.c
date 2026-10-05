#include <stdio.h>

int path[30];
int path_len;

void backtrack(int* candidates, int candidatesSize, int start, int remain) {
    if (remain == 0) {
        for (int i = 0; i < path_len; i++) {
            printf("%d", path[i]);
            if (i + 1 < path_len) {
                printf(" ");
            }
        }
        printf("\n");
        return;
    }
    if (remain < 0) {
        return;
    }
    for (int i = start; i < candidatesSize; i++) {
        path[path_len++] = candidates[i];
        backtrack(candidates, candidatesSize, i, remain - candidates[i]);
        path_len--;
    }
}

void combinationSum(int* candidates, int candidatesSize, int target) {
    path_len = 0;
    backtrack(candidates, candidatesSize, 0, target);
}

int main() {
    int c1[] = {2, 3, 6, 7};
    combinationSum(c1, 4, 7);

    int c2[] = {2, 3, 5};
    combinationSum(c2, 3, 8);

    int c3[] = {2};
    combinationSum(c3, 1, 1);

    return 0;
}
