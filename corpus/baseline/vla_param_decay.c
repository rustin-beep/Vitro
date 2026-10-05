// @category: baseline
int sum(int n, int a[n]) { int s = 0; for (int i = 0; i < n; i++) s += a[i]; return s; } int main() { int arr[3] = {1,2,3}; printf("%d", sum(3, arr)); return 0; }
