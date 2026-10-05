// @category: baseline
void countingSort(int arr[], int n) { int count[10] = {0}; for (int i = 0; i < n; i++) count[arr[i]]++; int index = 0; for (int i = 0; i < 10; i++) while (count[i] > 0) { arr[index++] = i; count[i]--; } } int main() { int arr[5] = {4,2,2,8,3}; countingSort(arr, 5); printf("%d %d %d %d %d", arr[0], arr[1], arr[2], arr[3], arr[4]); return 0; }
