// @category: baseline
typedef int (*Op)(int, int); int add(int a, int b) { return a+b; } int main() { Op op = add; printf("%d", op(2,3)); return 0; }
