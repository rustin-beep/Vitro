#include <stdio.h>

int main() {
    int a[5] = {10, 20, 30, 40, 50};
    int* p = a;
    int i = 1;
    p += i++;
    printf("%d %d\n", *p, i);
    return 0;
}
