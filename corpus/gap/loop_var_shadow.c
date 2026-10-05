// @category: scope_bug
int main() { int i = 10; for (int i = 0; i < 3; i++) printf("%d", i); printf("%d", i); return 0; }
