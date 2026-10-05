// @category: baseline
union U { int i; }; int main() { union U arr[2]; arr[0].i = 1; arr[1].i = 2; printf("%d", arr[1].i); return 0; }
