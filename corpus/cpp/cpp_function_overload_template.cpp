#include <stdio.h>
int max(int a, int b) { return a > b ? a : b; }
template<class T>
T tmax(T a, T b) { return a > b ? a : b; }
int main() {
    printf("%d\n", max(3, 5));
    printf("%f\n", tmax(2.5, 1.5));
    printf("%d\n", tmax(7, 4));
    return 0;
}
