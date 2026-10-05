// @category: baseline
int apply(int (*op)(int), int x) { return op(x); } int inc(int n) { return n+1; } int main() { printf("%d", apply(inc, 5)); return 0; }
