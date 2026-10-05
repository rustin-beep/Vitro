#include <stdio.h>

void spiralOrder(int* matrix, int rows, int cols) {
    int result[100];
    int size = 0;
    if (rows == 0) return;
    int top = 0, bottom = rows - 1;
    int left = 0, right = cols - 1;
    while (top <= bottom && left <= right) {
        for (int j = left; j <= right; j++) result[size++] = matrix[top * cols + j];
        top++;
        for (int i = top; i <= bottom; i++) result[size++] = matrix[i * cols + right];
        right--;
        if (top <= bottom) {
            for (int j = right; j >= left; j--) result[size++] = matrix[bottom * cols + j];
            bottom--;
        }
        if (left <= right) {
            for (int i = bottom; i >= top; i--) result[size++] = matrix[i * cols + left];
            left++;
        }
    }
    for (int i = 0; i < size; i++) printf("%d\n", result[i]);
}

int main() {
    int m[] = {1, 2, 3, 4, 5, 6, 7, 8, 9};
    spiralOrder(m, 3, 3);
    return 0;
}
