// @category: baseline
int gcd(int a, int b) { while (b != 0) { int temp = b; b = a % b; a = temp; } return a; } int main() { printf("%d", gcd(48, 18)); return 0; }
