#include <stdio.h>

int main() {
    int a[5] = {10, 20, 30, 40, 50};
    int* p = a;
    p += 2;
    printf("%d\n", *p);
    p += 0;
    printf("%d\n", *p);
    p -= 1;
    printf("%d\n", *p);
    return 0;
}
