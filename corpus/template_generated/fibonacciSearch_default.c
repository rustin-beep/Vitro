// @category: baseline
#include <stdio.h>

int fib[20];

void initFib() {
    fib[0] = 0;
    fib[1] = 1;
    for (int i = 2; i < 20; i++)
        fib[i] = fib[i - 1] + fib[i - 2];
}

int fibonacciSearch(int arr[], int n, int key) {
    int k = 0;
    while (fib[k] < n + 1) k++;
    int temp[20];
    for (int i = 0; i < n; i++) temp[i] = arr[i];
    for (int i = n; i < fib[k]; i++) temp[i] = arr[n - 1];
    int low = 0, high = n - 1;
    while (low <= high) {
        int mid = low + fib[k - 1] - 1;
        if (key < temp[mid]) {
            high = mid - 1;
            k = k - 1;
        } else if (key > temp[mid]) {
            low = mid + 1;
            k = k - 2;
        } else {
            if (mid < n) return mid;
            else return n - 1;
        }
    }
    return -1;
}

int main() {
    initFib();
    int arr[] = {10, 20, 30, 40, 50, 60, 70, 80};
    int n = 8;
    int key = 30;
    int result = fibonacciSearch(arr, n, key);
    printf("%d\n", result);
    return 0;
}

