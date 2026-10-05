// @category: baseline
struct S { int arr[3]; }; int main() { struct S s; s.arr[1] = 5; printf("%d", s.arr[1]); return 0; }
