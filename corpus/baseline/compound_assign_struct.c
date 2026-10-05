// @category: baseline
struct S { int x; }; int main() { struct S s; s.x = 10; s.x += 5; printf("%d", s.x); return 0; }
