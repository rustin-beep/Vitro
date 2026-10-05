// @category: baseline
int cmp(const void* a, const void* b) { return *(int*)a - *(int*)b; } int main() { int a[3] = {3,1,2}; qsort(a, 3, 4, cmp); printf("%d", a[0]); return 0; }
