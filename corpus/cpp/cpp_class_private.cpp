#include <stdio.h>
class Box {
    int v;
public:
    Box() { v = 7; }
    int get() { return v; }
};
int main() {
    Box b;
    printf("%d\n", b.get());
    return 0;
}
