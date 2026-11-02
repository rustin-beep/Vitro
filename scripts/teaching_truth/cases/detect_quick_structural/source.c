#include <stdio.h>

/* M33b A3 红例：结构分支快排形态 A——递归主函数调 partition、无嵌套循环
   （嵌套循环在 partition 内部），has_nested_loops && has_partition_pattern &&
   is_recursive 三特征同函数共存判据不可满足，双双漏检。真值：quick_sort。 */
int mySort(int arr[], int low, int high);

int myPartition(int arr[], int low, int high) {
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
    return i + 1;
}

int mySort(int arr[], int low, int high) {
    if (low < high) {
        int p = myPartition(arr, low, high);
        mySort(arr, low, p - 1);
        mySort(arr, p + 1, high);
    }
    return 0;
}

int main() {
    int arr[5] = {10, 7, 1, 9, 50};
    mySort(arr, 0, 4);
    for (int i = 0; i < 5; i++) {
        printf("%d ", arr[i]);
    }
    printf("\n");
    return 0;
}
