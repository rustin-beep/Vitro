// @category: baseline
struct S { int a; int b; }; int main() { struct S s; memset(&s, 0, sizeof(s)); printf("%d", s.a); return 0; }
