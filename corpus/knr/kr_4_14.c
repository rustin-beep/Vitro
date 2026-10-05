#include <stdio.h>
#define swap(t, x, y) { t temp = x; x = y; y = temp; }
int main() {
    int a = 3, b = 5;
    swap(int, a, b);
    printf("%d %d\n", a, b);
    float x = 1.5, y = 2.5;
    swap(float, x, y);
    printf("%.1f %.1f\n", x, y);
    return 0;
}
