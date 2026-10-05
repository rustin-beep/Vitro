// @category: baseline
struct S { int x; }; int main() { struct S a; a.x = 1; struct S b = a; printf("%d", b.x); return 0; }
