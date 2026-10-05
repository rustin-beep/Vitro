#include <stdio.h>
template<class T>
T add(T a, T b) { return a + b; }
int main() {
    printf("%d\n", add(4, 5));
    return 0;
}
