// @category: baseline
struct S { int a; }; union U { int i; float f; }; int main() { printf("%d %d", sizeof(struct S), sizeof(union U)); return 0; }
