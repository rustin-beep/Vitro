// @category: baseline
int main() { int* p = malloc(8); p[0] = 1; p[1] = 2; p = realloc(p, 4); printf("%d", p[0]); free(p); return 0; }
