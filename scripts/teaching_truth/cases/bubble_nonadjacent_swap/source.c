#include <stdio.h>

/* 函数名 bubbleSort 但体内是非相邻比较交换（M34b A7 / M30 A1-1 红例载体）：
   detect 命名分支命中 bubble_sort，推断器 compare/swap 文案右侧下标恒拼
   j+1——行文本 `arr[i] > arr[j]` 与 `arr[i] = arr[j]` 的真下标对是 (i, j)
   非相邻。真值：文案下标 ⊆ 源码行下标表达式用帧变量求值集。 */
void bubbleSort(int arr[], int n) {
    for (int i = 0; i < n - 1; i++) {
        for (int j = i + 1; j < n; j++) {
            if (arr[i] > arr[j]) {
                int temp = arr[i];
                arr[i] = arr[j];
                arr[j] = temp;
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
