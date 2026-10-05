// @category: baseline
#include <stdio.h>

void bucketSort(int arr[], int n) {
    int bucket[10][10];
    int count[10] = {0};
    int max = arr[0];
    for (int i = 1; i < n; i++)
        if (arr[i] > max) max = arr[i];
    for (int i = 0; i < n; i++) {
        int idx = (arr[i] * 10) / (max + 1);
        bucket[idx][count[idx]++] = arr[i];
    }
    for (int i = 0; i < 10; i++) {
        for (int j = 0; j < count[i] - 1; j++) {
            for (int k = 0; k < count[i] - j - 1; k++) {
                if (bucket[i][k] > bucket[i][k + 1]) {
                    int temp = bucket[i][k];
                    bucket[i][k] = bucket[i][k + 1];
                    bucket[i][k + 1] = temp;
                }
            }
        }
    }
    int idx = 0;
    for (int i = 0; i < 10; i++) {
        for (int j = 0; j < count[i]; j++)
            arr[idx++] = bucket[i][j];
    }
}

int main() {
    int arr[] = {29, 25, 3, 49, 9, 37, 21, 43};
    int n = 8;
    bucketSort(arr, n);
    for (int i = 0; i < n; i++)
        printf("%d ", arr[i]);
    printf("\n");
    return 0;
}

