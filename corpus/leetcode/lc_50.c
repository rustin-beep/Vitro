#include <stdio.h>

double myPow(double x, int n) {
    if (n == 0) return 1.0;
    int exp = n;
    if (exp < 0) {
        x = 1.0 / x;
        exp = -exp;
    }
    double result = 1.0;
    double base = x;
    while (exp > 0) {
        if (exp & 1) result = result * base;
        base = base * base;
        exp = exp >> 1;
    }
    return result;
}

int main() {
    printf("%f\n", myPow(2.0, 10));
    printf("%f\n", myPow(2.1, 3));
    printf("%f\n", myPow(2.0, -2));
    return 0;
}
