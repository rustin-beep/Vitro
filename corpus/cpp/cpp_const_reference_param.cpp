#include <stdio.h>
void show(const int& x) { printf("%d\n", x); }
int sum(const int& a, const int& b) { return a + b; }
int main() {
    show(42);
    int n = 7;
    show(n);
    show(n + 3);
    printf("%d\n", sum(10, 20));
    return 0;
}
