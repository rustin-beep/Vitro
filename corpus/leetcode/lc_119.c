#include <stdio.h>
#include <stdlib.h>

int* getRow(int rowIndex, int* returnSize) {
    *returnSize = rowIndex + 1;
    int* row = (int*)malloc(sizeof(int) * (*returnSize));
    row[0] = 1;
    for (int i = 1; i <= rowIndex; i++) {
        row[i] = 1;
        for (int j = i - 1; j > 0; j--) {
            row[j] = row[j] + row[j - 1];
        }
    }
    return row;
}

int main() {
    int returnSize1 = 0;
    int* r1 = getRow(3, &returnSize1);
    for (int i = 0; i < returnSize1; i++) {
        if (i > 0) printf(" ");
        printf("%d", r1[i]);
    }
    printf("\n");
    free(r1);

    int returnSize2 = 0;
    int* r2 = getRow(0, &returnSize2);
    for (int i = 0; i < returnSize2; i++) {
        if (i > 0) printf(" ");
        printf("%d", r2[i]);
    }
    printf("\n");
    free(r2);

    int returnSize3 = 0;
    int* r3 = getRow(1, &returnSize3);
    for (int i = 0; i < returnSize3; i++) {
        if (i > 0) printf(" ");
        printf("%d", r3[i]);
    }
    printf("\n");
    free(r3);

    return 0;
}
