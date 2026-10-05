// @category: baseline
struct S { int x; }; int main() { struct S s; struct S* p = &s; p->x = 7; printf("%d", p->x); return 0; }
