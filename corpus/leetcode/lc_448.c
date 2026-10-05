#include <stdio.h>
#include <stdlib.h>

int abs_(int x) { return x < 0 ? -x : x; }

int* findDisappearedNumbers(int* nums, int numsSize, int* returnSize) {
    int* res = (int*)malloc(numsSize * sizeof(int));
    *returnSize = 0;
    for (int i = 0; i < numsSize; i++) {
        int idx = abs_(nums[i]) - 1;
        if (nums[idx] > 0) nums[idx] = -nums[idx];
    }
    for (int i = 0; i < numsSize; i++) {
        if (nums[i] > 0) {
            int idx = *returnSize;
            res[idx] = i + 1;
            *returnSize = *returnSize + 1;
        }
    }
    return res;
}

int main(void) {
    int a1[] = {4,3,2,7,8,2,3,1};
    int s1 = 0;
    int* r1 = findDisappearedNumbers(a1, 8, &s1);
    for (int i = 0; i < s1; i++) printf("%d ", r1[i]);
    printf("\n");
    free(r1);

    int a2[] = {1,1};
    int s2 = 0;
    int* r2 = findDisappearedNumbers(a2, 2, &s2);
    for (int i = 0; i < s2; i++) printf("%d ", r2[i]);
    printf("\n");
    free(r2);
    return 0;
}
