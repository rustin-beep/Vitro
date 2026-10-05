// @category: baseline
int main() { int a[3] = {3,1,2}; int m = a[0]; for (int i = 1; i < 3; i++) if (a[i] > m) m = a[i]; printf("%d", m); return 0; }
