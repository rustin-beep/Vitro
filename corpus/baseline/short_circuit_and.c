// @category: baseline
int f() { printf("call"); return 1; } int main() { int x = 0; if (x && f()) printf("yes"); printf("done"); return 0; }
