// @category: baseline
int main() { int a[5] = {1,3,5,7,9}; int key = 7, found = -1; for (int i = 0; i < 5; i++) if (a[i] == key) { found = i; break; } printf("%d", found); return 0; }
