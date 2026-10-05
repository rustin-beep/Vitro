#include <stdio.h>
void inc(int& x) { x = x + 1; }
int main() {
    int a = 5;
    inc(a);
    printf("%d\n", a);
    return 0;
}
