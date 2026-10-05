#include <stdio.h>

int main() {
    volatile int x = 10;
    volatile int y;
    y = x + 5;
    printf("%d\n", y);
    x = 20;
    printf("%d\n", x);
    return 0;
}
