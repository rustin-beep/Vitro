// @category: baseline
#include <stdio.h>
#include <time.h>
int main() {
    time_t a = 100, b = 40;
    printf("%.1f", difftime(a, b));
    return 0;
}
