// @category: baseline
int add(int a) { return a+1; } int main() { int (*fp)(int) = add; int (**pp)(int) = &fp; printf("%d", (*pp)(5)); return 0; }
