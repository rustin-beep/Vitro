#include <stdio.h>

/* 内联分区的快排（M34b A5 红例载体）：取枢轴行 `int pivot = arr[high];`
   与分区逻辑都在 quickSort 函数体内（collector 按帧所在函数名找算法匹配，
   独立 partition 函数内的帧不分派——A5 端到端触发须内联）。判据
   contains("pivot") && contains("=") 对取枢轴行命中 partition_init，文案
   「枢轴落位下标 pivot=50」把**值** 50 当下标。真值：下标域 [0, n-1]。 */
void quickSort(int arr[], int low, int high) {
    if (low < high) {
        int pivot = arr[high];
        int i = low - 1;
        for (int j = low; j < high; j++) {
            if (arr[j] <= pivot) {
                i++;
                int temp = arr[i];
                arr[i] = arr[j];
                arr[j] = temp;
            }
        }
        int temp = arr[i + 1];
        arr[i + 1] = arr[high];
        arr[high] = temp;
        int p = i + 1;
        quickSort(arr, low, p - 1);
        quickSort(arr, p + 1, high);
    }
}

int main() {
    int arr[5] = {10, 7, 1, 9, 50};
    int n = 5;
    quickSort(arr, 0, n - 1);
    for (int i = 0; i < n; i++) {
        printf("%d ", arr[i]);
    }
    printf("\n");
    return 0;
}
