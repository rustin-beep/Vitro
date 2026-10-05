// @category: baseline
int main() { int x = 5; int* p = &x; int** pp = &p; void* vp = pp; int** pp2 = (int**)vp; printf("%d", **pp2); return 0; }
