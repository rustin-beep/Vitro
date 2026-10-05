#include <stdio.h>
class Counter {
public:
    int v;
    Counter() { v = 0; }
    void inc() { v = v + 1; }
    int get() { return v; }
};
int main() {
    Counter c;
    c.inc();
    c.inc();
    printf("%d\n", c.get());
    return 0;
}
