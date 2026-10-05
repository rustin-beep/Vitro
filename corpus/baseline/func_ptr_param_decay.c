// @category: baseline
int sum(int a[]) { int s = 0; for (int i = 0; i < 3; i++) s += a[i]; return s; } int main() { int arr[3] = {1,2,3}; printf("%d", sum(arr)); return 0; }
