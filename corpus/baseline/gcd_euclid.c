// @category: baseline
int gcd(int a, int b) { while (b != 0) { int t = b; b = a % b; a = t; } return a; } int main() { printf("%d", gcd(48, 18)); return 0; }
