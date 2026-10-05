#include <stdio.h>
int main() {
    char buf[] = "1 2 3";
    int a, b, c;
    sscanf(buf, "%d %d %d", &a, &b, &c);
    printf("sum=%d\n", a + b + c);
    return 0;
}
