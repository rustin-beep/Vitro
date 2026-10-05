// @category: baseline
#include <stdio.h>

void swap(int* a, int* b) {
    int temp = *a;
    *a = *b;
    *b = temp;
}

int main() {
    int x = 3, y = 5;
    swap(&x, &y);
    printf("x=%d y=%d\n", x, y);
    return 0;
}

