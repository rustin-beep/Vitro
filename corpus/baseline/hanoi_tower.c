// @category: baseline
void hanoi(int n, char from, char to, char aux) { if (n == 1) { printf("Move 1 from %c to %c\n", from, to); return; } hanoi(n - 1, from, aux, to); printf("Move %d from %c to %c\n", n, from, to); hanoi(n - 1, aux, to, from); } int main() { hanoi(2, 'A', 'C', 'B'); return 0; }
