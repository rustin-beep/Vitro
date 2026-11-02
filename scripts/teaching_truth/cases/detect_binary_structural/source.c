#include <stdio.h>

/* M33b A2 红例：无命名的教科书二分（left = mid + 1 是 Identifier 赋值非
   arr[mid] 形态）——binary_search 结构分支的 has_left_right_update 判据
   恒不可达，零检测。真值：应识别为 binary_search。 */
int myFind(int arr[], int n, int target) {
    int left = 0, right = n - 1;
    while (left <= right) {
        int mid = (left + right) / 2;
        if (arr[mid] == target) return mid;
        else if (arr[mid] < target) left = mid + 1;
        else right = mid - 1;
    }
    return -1;
}

int main() {
    int arr[5] = {1, 3, 5, 7, 9};
    printf("%d\n", myFind(arr, 5, 7));
    return 0;
}
