#include <stdio.h>

int main() {
    char a[32], b[32];
    int n;
    char src[] = "hello world 42";
    sscanf(src, "%s %s %d", a, b, &n);
    printf("[%s] [%s] [%d]\n", a, b, n);
    return 0;
}
