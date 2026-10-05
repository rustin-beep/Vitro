// @category: baseline
int main() { int x = 5; void* p = (void*)&x; int* q = (int*)p; printf("%d", *q); return 0; }
