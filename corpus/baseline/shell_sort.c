// @category: baseline
void shellSort(int arr[], int n) { for (int gap = n/2; gap > 0; gap /= 2) for (int i = gap; i < n; i++) { int temp = arr[i]; int j; for (j = i; j >= gap && arr[j-gap] > temp; j -= gap) arr[j] = arr[j-gap]; arr[j] = temp; } } int main() { int arr[5] = {64,34,25,12,22}; shellSort(arr, 5); printf("%d %d %d %d %d", arr[0], arr[1], arr[2], arr[3], arr[4]); return 0; }
