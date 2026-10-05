// @category: baseline
int main() { int* p = malloc(4); *p = 1; p = realloc(p, 8); printf("%d", *p); free(p); return 0; }
