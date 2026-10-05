#include <stdio.h>

double return_double_literal(void) {
    return 2.5;
}

double return_double_var(void) {
    double x = 3.75;
    return x;
}

double return_int_as_double(void) {
    return 42;
}

float return_float_literal(void) {
    return 1.5f;
}

int main() {
    printf("%.5f\n", return_double_literal());
    printf("%.5f\n", return_double_var());
    printf("%.5f\n", return_int_as_double());
    printf("%.5f\n", return_float_literal());
    return 0;
}
