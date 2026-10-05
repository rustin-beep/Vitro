#include <stdio.h>
void add(int& x, int y) { x = x + y; }
void scale(int& x, int f) { x = x * f; }
int main() {
    int a = 5;
    add(a, 3);
    scale(a, 2);
    printf("%d\n", a);
    return 0;
}
