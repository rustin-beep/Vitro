#include <stdio.h>

int main() {
    int a[5] = {10, 20, 30, 40, 50};
    int* p = a + 3;
    p += -1;
    printf("%d\n", *p);
    p -= 2;
    printf("%d\n", *p);
    return 0;
}
