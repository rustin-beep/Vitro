// @category: baseline
#include <stdio.h>

void RadixSort(int arr[], int n) {
    int max = arr[0];
    for (int i = 1; i < n; i++) {
        if (arr[i] > max) max = arr[i];
    }
    int exp;
    int output[10];
    int count[10];
    for (exp = 1; max / exp > 0; exp *= 10) {
        for (int i = 0; i < 10; i++) count[i] = 0;
        for (int i = 0; i < n; i++) count[(arr[i] / exp) % 10]++;
        for (int i = 1; i < 10; i++) count[i] += count[i - 1];
        for (int i = n - 1; i >= 0; i--) {
            output[count[(arr[i] / exp) % 10] - 1] = arr[i];
            count[(arr[i] / exp) % 10]--;
        }
        for (int i = 0; i < n; i++) arr[i] = output[i];
    }
}

int main() {
    int arr[7] = {170, 45, 75, 90, 2, 802, 24};
    int n = 7;
    RadixSort(arr, n);
    for (int i = 0; i < n; i++) printf("%d ", arr[i]);
    printf("\n");
    return 0;
}

