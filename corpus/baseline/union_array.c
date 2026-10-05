// @category: baseline
union U { int i; float f; }; int main() { union U arr[2]; arr[0].i = 42; printf("%d", arr[0].i); return 0; }
