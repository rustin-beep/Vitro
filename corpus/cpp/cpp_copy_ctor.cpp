#include <stdio.h>

class Box {
public:
    int* p;
    Box(int v) {
        p = new int(v);
    }
    Box(const Box& other) {
        p = new int(*other.p);
    }
    ~Box() {
        delete p;
    }
    int value() {
        return *p;
    }
};

int main() {
    Box a(5);
    Box b(a);
    Box c = a;
    printf("%d %d %d\n", a.value(), b.value(), c.value());
    *b.p = 10;
    printf("%d %d %d\n", a.value(), b.value(), c.value());
    return 0;
}
