#include <stdio.h>

int main() {
    int a = 1, b = 2, c = 3;
    int* arr[3];
    arr[0] = &a;
    arr[1] = &b;
    arr[2] = &c;
    int** pp = arr;
    pp += 1;
    printf("%d\n", **pp);
    return 0;
}
