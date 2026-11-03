#include <stdio.h>

/* 无 -i 变体冒泡（M34b A2 红例载体）：内层界 `j < n - 1`——教科书
   「未优化冒泡」写法。推断器守卫 j_in_inner_range 取模板界 n-1-i，
   i≥1 后 j ∈ [n-1-i, n-2] 的比较/交换帧被吞。真值：n=5 时比较 16 次。 */
void bubbleSort(int arr[], int n) {
    for (int i = 0; i < n - 1; i++) {
        for (int j = 0; j < n - 1; j++) {
            if (arr[j] > arr[j + 1]) {
                int temp = arr[j];
                arr[j] = arr[j + 1];
                arr[j + 1] = temp;
            }
        }
    }
}

int main() {
    int arr[5] = {5, 3, 8, 1, 2};
    int n = 5;
    bubbleSort(arr, n);
    for (int i = 0; i < n; i++) {
        printf("%d ", arr[i]);
    }
    printf("\n");
    return 0;
}
