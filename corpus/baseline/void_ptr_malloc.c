// @category: baseline
int main() { int* p = (int*)malloc(4); *p = 42; printf("%d", *p); free(p); return 0; }
