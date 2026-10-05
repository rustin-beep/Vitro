// @category: baseline
int init() { static int v = 10; v++; return v; }
int main() { printf("%d %d", init(), init()); return 0; }
