// @category: baseline
int f1() { return 1; } int f2() { return 2; } int main() { int (*fp[2])() = {f1,f2}; printf("%d %d", fp[0](), fp[1]()); return 0; }
