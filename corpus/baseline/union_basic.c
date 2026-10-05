// @category: baseline
union U { int i; float f; }; int main() { union U u; u.i = 1; printf("%d", u.i); return 0; }
