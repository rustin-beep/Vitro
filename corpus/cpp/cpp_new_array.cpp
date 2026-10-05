#include <stdio.h>
int g = 0;
class A {
public:
    A() { g++; }
    ~A() { g--; }
};
int main() {
    A* arr = new A[3];
    printf("%d\n", g);
    delete[] arr;
    printf("%d\n", g);
    return 0;
}
