#include <stdio.h>
class Counter {
public:
    int v;
    Counter() { v = 0; }
    Counter* inc() { v = v + 1; return this; }
    int get() { return v; }
};
int main() {
    Counter c;
    c.inc()->inc()->inc();
    printf("%d\n", c.get());
    return 0;
}
