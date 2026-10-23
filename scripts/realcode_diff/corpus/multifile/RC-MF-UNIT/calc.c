#include "calc.h"
#include <stddef.h>

int calc_add(int a, int b)
{
    return a + b;
}

int calc_sub(int a, int b)
{
    return a - b;
}

int calc_mul(int a, int b)
{
    return a * b;
}

int calc_div(int a, int b)
{
    if (b == 0) {
        return 0;
    }
    return a / b;
}

int calc_safe_div(int a, int b, int *out)
{
    if (b == 0) {
        return -1;
    }
    if (out != NULL) {
        *out = a / b;
    }
    return 0;
}

int calc_clamp(int value, int low, int high)
{
    if (value < low) {
        return low;
    }
    if (value > high) {
        return high;
    }
    return value;
}

int calc_sum_to(int n)
{
    int total = 0;
    int i;

    if (n < 0) {
        return 0;
    }
    for (i = 1; i <= n; i++) {
        total += i;
    }
    return total;
}
