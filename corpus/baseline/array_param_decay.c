// @category: baseline
int sum(int a[], int n) { int s = 0; for (int i = 0; i < n; i++) s += a[i]; return s; } int main() { int arr[3] = {1,2,3}; printf("%d", sum(arr, 3)); return 0; }
