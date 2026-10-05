#include <stdio.h>
#include <stdlib.h>

int compare(const void* a, const void* b) {
    return (*(int*)a - *(int*)b);
}

int result[100][20];
int resultSize;
int resultColSize[100];

void backtrack(int* candidates, int candidatesSize, int target, int start, int* path, int pathSize) {
    if (target == 0) {
        resultColSize[resultSize] = pathSize;
        for (int i = 0; i < pathSize; i++) result[resultSize][i] = path[i];
        resultSize++;
        return;
    }
    for (int i = start; i < candidatesSize; i++) {
        if (i > start && candidates[i] == candidates[i - 1]) continue;
        if (candidates[i] > target) break;
        path[pathSize] = candidates[i];
        backtrack(candidates, candidatesSize, target - candidates[i], i + 1, path, pathSize + 1);
    }
}

int main() {
    int candidates[] = {10, 1, 2, 7, 6, 1, 5};
    qsort(candidates, 7, sizeof(int), compare);
    int path[20];
    resultSize = 0;
    backtrack(candidates, 7, 8, 0, path, 0);
    printf("%d\n", resultSize);
    for (int i = 0; i < resultSize; i++) {
        for (int j = 0; j < resultColSize[i]; j++) {
            printf("%d", result[i][j]);
            if (j < resultColSize[i] - 1) printf(" ");
        }
        printf("\n");
    }
    return 0;
}
