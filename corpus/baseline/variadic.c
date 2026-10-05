#include <stdio.h>
#include <stdarg.h>

int sum_int(int count, ...) {
    va_list ap;
    va_start(ap, count);
    int total = 0;
    for (int i = 0; i < count; i++) {
        total += va_arg(ap, int);
    }
    va_end(ap);
    return total;
}

double sum_double(int count, ...) {
    va_list ap;
    va_start(ap, count);
    double total = 0.0;
    for (int i = 0; i < count; i++) {
        total += va_arg(ap, double);
    }
    va_end(ap);
    return total;
}

long long sum_longlong(int count, ...) {
    va_list ap;
    va_start(ap, count);
    long long total = 0;
    for (int i = 0; i < count; i++) {
        total += va_arg(ap, long long);
    }
    va_end(ap);
    return total;
}

int main() {
    printf("%d\n", sum_int(3, 10, 20, 30));
    printf("%.1f\n", sum_double(3, 1.5, 2.5, 3.5));
    printf("%lld\n", sum_longlong(3, 10000000000LL, 20000000000LL, 30000000000LL));
    return 0;
}
