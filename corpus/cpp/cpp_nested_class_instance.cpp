#include <stdio.h>

class Outer {
public:
    class Inner {
    public:
        int x;
        Inner(int v = 0) { x = v; }
        int get() { return x; }
    };
};

void print_inner(Outer::Inner obj) {
    printf("%d\n", obj.get());
}

int main() {
    Outer::Inner a;
    Outer::Inner b(10);
    Outer::Inner* p = &b;

    printf("%d\n", a.get());
    printf("%d\n", b.get());
    printf("%d\n", p->get());

    print_inner(b);

    return 0;
}
