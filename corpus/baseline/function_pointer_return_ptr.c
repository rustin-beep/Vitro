// @category: baseline
int* greet(int x) { static int r = 0; r = x; return &r; } int main() { int* (*fp)(int) = greet; int* p = fp(42); printf("%d", *p); return 0; }
