// @category: baseline
struct S { int x; }; int main() { struct S arr[2]; struct S* p = arr; p++; printf("%d", p == &arr[1]); return 0; }
