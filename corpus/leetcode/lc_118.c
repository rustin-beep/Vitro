#include <stdio.h>
#include <stdlib.h>

int** generate(int numRows, int* returnSize, int** returnColumnSizes) {
    int** result = (int**)malloc(sizeof(int*) * numRows);
    *returnSize = numRows;
    *returnColumnSizes = (int*)malloc(sizeof(int) * numRows);
    for (int i = 0; i < numRows; i++) {
        result[i] = (int*)malloc(sizeof(int) * (i + 1));
        (*returnColumnSizes)[i] = i + 1;
        result[i][0] = 1;
        result[i][i] = 1;
        for (int j = 1; j < i; j++) {
            result[i][j] = result[i - 1][j - 1] + result[i - 1][j];
        }
    }
    return result;
}

int main() {
    int returnSize = 0;
    int* colSizes = NULL;
    int** r = generate(5, &returnSize, &colSizes);
    for (int i = 0; i < returnSize; i++) {
        for (int j = 0; j < colSizes[i]; j++) {
            if (j > 0) printf(" ");
            printf("%d", r[i][j]);
        }
        printf("\n");
        free(r[i]);
    }
    free(r);
    free(colSizes);
    return 0;
}
