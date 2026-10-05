// @category: baseline
int mul(int a, int b) { return a*b; } int divi(int a, int b) { return a/b; } int main() { int (*ops[2])(int, int) = {mul, divi}; printf("%d %d", ops[0](3,4), ops[1](8,2)); return 0; }
