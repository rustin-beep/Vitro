// @category: baseline
struct S { int a; int b; }; int main() { struct S s1 = {1, 2}; struct S s2 = s1; printf("%d %d", s2.a, s2.b); return 0; }
