#include <stdio.h>
template<class T>
T add(T a, T b) { return a + b; }
template<class T>
T maxVal(T a, T b) { return a > b ? a : b; }
int main() {
    printf("%d\n", add(1, 2));
    printf("%f\n", add(1.5, 2.5));
    printf("%d\n", maxVal(3, 7));
    return 0;
}
