// @category: baseline
int add(int a, int b) { return a+b; } int main() { typedef int (*Op)(int, int); Op op = add; printf("%d", op(2,3)); return 0; }
