// @category: baseline
#include <stdio.h>

void countingSort(int arr[], int n) {
    int count[10] = {0};
    for (int i = 0; i < n; i++) {
        count[arr[i]]++;
    }
    int index = 0;
    for (int i = 0; i < 10; i++) {
        while (count[i] > 0) {
            arr[index++] = i;
            count[i]--;
        }
    }
}

int main() {
    int arr[5] = {4, 2, 2, 8, 3};
    int n = 5;
    countingSort(arr, n);
    for (int i = 0; i < n; i++) {
        printf("%d ", arr[i]);
    }
    printf("\n");
    return 0;
}

