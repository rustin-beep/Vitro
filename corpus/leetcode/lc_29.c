#include <stdio.h>
#include <limits.h>

int divide(int dividend, int divisor) {
    if (dividend == INT_MIN && divisor == -1) return INT_MAX;
    if (divisor == 1) return dividend;
    if (divisor == -1) return -dividend;
    int sign = 1;
    if ((dividend < 0 && divisor > 0) || (dividend > 0 && divisor < 0)) sign = -1;
    int dvd = dividend;
    int dvs = divisor;
    if (dvd < 0) dvd = -dvd;
    if (dvs < 0) dvs = -dvs;
    int result = 0;
    while (dvd >= dvs) {
        dvd -= dvs;
        result++;
    }
    return sign == 1 ? result : -result;
}

int main() {
    printf("%d\n", divide(10, 3));
    printf("%d\n", divide(7, -3));
    printf("%d\n", divide(1, 1));
    return 0;
}
