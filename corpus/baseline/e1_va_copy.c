// @category: baseline
// E1 B 档：va_copy
#include <stdio.h>
#include <stdarg.h>
double sum_twice(int n, ...) {
    va_list ap, ap2;
    va_start(ap, n);
    va_copy(ap2, ap);
    double s = 0, t = 0;
    for (int i = 0; i < n; i++) s += va_arg(ap, double);
    for (int i = 0; i < n; i++) t += va_arg(ap2, double);
    va_end(ap2);
    va_end(ap);
    return s + t;
}
int main() {
    printf("%.1f %.1f\n", sum_twice(2, 1.5, 2.5), sum_twice(3, 1.0, 2.0, 3.5));
    return 0;
}
