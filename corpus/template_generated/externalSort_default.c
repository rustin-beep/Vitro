// @category: baseline
#include <stdio.h>
#define MAX 4

void replacementSelection(int arr[], int n) {
    int heap[MAX];
    int heapSize = n < MAX ? n : MAX;
    for (int i = 0; i < heapSize; i++) heap[i] = arr[i];
    int idx = heapSize;
    int output[30];
    int outCount = 0;
    while (heapSize > 0) {
        int minIdx = 0;
        for (int i = 1; i < heapSize; i++)
            if (heap[i] < heap[minIdx]) minIdx = i;
        output[outCount++] = heap[minIdx];
        if (idx < n) {
            int next = arr[idx++];
            if (next >= heap[minIdx])
                heap[minIdx] = next;
            else {
                heap[minIdx] = heap[heapSize - 1];
                heap[heapSize - 1] = next;
                heapSize--;
            }
        } else {
            heap[minIdx] = heap[heapSize - 1];
            heapSize--;
        }
    }
    for (int i = 0; i < outCount; i++)
        printf("%d ", output[i]);
    printf("\n");
}

int main() {
    int arr[] = {51, 49, 39, 46, 38, 29, 14, 61, 15, 30, 1, 48, 52, 3, 63, 27, 4, 13, 89, 21, 53, 5, 34};
    int n = 23;
    replacementSelection(arr, n);
    return 0;
}

