#include <stdio.h>

void setZeroes(int* matrix, int rows, int cols) {
    int first_row_zero = 0;
    int first_col_zero = 0;

    for (int c = 0; c < cols; c++) {
        if (matrix[c] == 0) {
            first_row_zero = 1;
            break;
        }
    }

    for (int r = 0; r < rows; r++) {
        if (matrix[r * cols] == 0) {
            first_col_zero = 1;
            break;
        }
    }

    for (int r = 1; r < rows; r++) {
        for (int c = 1; c < cols; c++) {
            if (matrix[r * cols + c] == 0) {
                matrix[r * cols] = 0;
                matrix[c] = 0;
            }
        }
    }

    for (int r = 1; r < rows; r++) {
        for (int c = 1; c < cols; c++) {
            if (matrix[r * cols] == 0 || matrix[c] == 0) {
                matrix[r * cols + c] = 0;
            }
        }
    }

    if (first_row_zero) {
        for (int c = 0; c < cols; c++) {
            matrix[c] = 0;
        }
    }

    if (first_col_zero) {
        for (int r = 0; r < rows; r++) {
            matrix[r * cols] = 0;
        }
    }
}

void printMatrix(int* matrix, int rows, int cols) {
    for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
            if (c > 0) {
                printf(" ");
            }
            printf("%d", matrix[r * cols + c]);
        }
        printf("\n");
    }
}

int main() {
    int m1[] = {1, 1, 1, 1, 0, 1, 1, 1, 1};
    setZeroes(m1, 3, 3);
    printMatrix(m1, 3, 3);
    printf("---\n");

    int m2[] = {0, 1, 2, 0, 3, 4, 5, 2, 1, 3, 1, 5};
    setZeroes(m2, 3, 4);
    printMatrix(m2, 3, 4);

    return 0;
}
