#include <stdio.h>
int g = 0;
class A {
public:
    int id;
    A(int i) { id = i; g = g * 10 + id; }
    ~A() { g = g * 10 + id + 5; }
};
int main() {
    A a(1);
    { A b(2); }
    printf("%d\n", g);
    return 0;
}
