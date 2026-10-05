// @category: baseline
#include <stdio.h>

int main() {
    int a = _Generic(1, int: 10, default: 20);
    int b = _Generic("hi", char*: 1, default: 0);
    int c = _Generic(2.5f, int: 1, float: 2, default: 3);
    printf("%d %d %d", a, b, c);
    return 0;
}
