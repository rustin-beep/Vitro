#include <stdio.h>

void rotate(int* matrix, int n) {
    for (int i = 0; i < n; i++) {
        for (int j = i + 1; j < n; j++) {
            int tmp = matrix[i * n + j];
            matrix[i * n + j] = matrix[j * n + i];
            matrix[j * n + i] = tmp;
        }
    }
    for (int i = 0; i < n; i++) {
        int left = 0;
        int right = n - 1;
        while (left < right) {
            int tmp = matrix[i * n + left];
            matrix[i * n + left] = matrix[i * n + right];
            matrix[i * n + right] = tmp;
            left++;
            right--;
        }
    }
}

int main() {
    int m1[9] = {1, 2, 3, 4, 5, 6, 7, 8, 9};
    rotate(m1, 3);
    for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 3; j++) {
            printf("%d ", m1[i * 3 + j]);
        }
        printf("\n");
    }
    int m2[16] = {5, 1, 9, 11, 2, 4, 8, 10, 13, 3, 6, 7, 15, 14, 12, 16};
    rotate(m2, 4);
    for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 4; j++) {
            printf("%d ", m2[i * 4 + j]);
        }
        printf("\n");
    }
    return 0;
}
