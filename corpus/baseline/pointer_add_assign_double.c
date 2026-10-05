#include <stdio.h>

int main() {
    double a[3] = {1.5, 2.5, 3.5};
    double* p = a;
    p += 2;
    printf("%.1f\n", *p);
    return 0;
}
