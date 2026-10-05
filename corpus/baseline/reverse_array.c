// @category: baseline
int main() { int a[5] = {1,2,3,4,5}; for (int i = 0; i < 2; i++) { int t = a[i]; a[i] = a[4-i]; a[4-i] = t; } printf("%d", a[0]); return 0; }
