// @category: baseline
union U { int i; float f; }; int main() { union U u; u.i = 42; printf("%d", u.i); return 0; }
