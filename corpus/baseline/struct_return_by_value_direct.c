// @category: baseline
struct S { int x; }; struct S make() { struct S s; s.x = 42; return s; } int main() { printf("%d", make().x); return 0; }
