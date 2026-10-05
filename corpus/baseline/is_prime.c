// @category: baseline
int isPrime(int n) { if (n <= 1) return 0; for (int i = 2; i * i <= n; i++) if (n % i == 0) return 0; return 1; } int main() { printf("%d", isPrime(17)); return 0; }
