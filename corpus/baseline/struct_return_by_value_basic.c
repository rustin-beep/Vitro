// @category: baseline
struct S { int x; }; struct S make() { struct S s; s.x = 42; return s; } int main() { struct S s = make(); printf("%d", s.x); return 0; }
