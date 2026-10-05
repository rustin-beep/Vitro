// @category: baseline
void swap(int* a, int* b) { int t = *a; *a = *b; *b = t; } int main() { int x = 1, y = 2; swap(&x, &y); printf("%d %d", x, y); return 0; }
