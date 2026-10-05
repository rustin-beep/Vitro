#include <stdio.h>

int fib(int n) {
    if (n <= 1) return n;
    int a = 0, b = 1;
    for (int i = 2; i <= n; i++) {
        int c = a + b;
        a = b;
        b = c;
    }
    return b;
}

int main() {
    printf("%d\n", fib(2));
    printf("%d\n", fib(3));
    printf("%d\n", fib(4));
    printf("%d\n", fib(10));
    return 0;
}
