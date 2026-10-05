// @category: baseline
int main() { int n = 123, s = 0; while (n > 0) { s += n % 10; n /= 10; } printf("%d", s); return 0; }
