#include <stdio.h>
class Box {
public:
    int v;
    Box() { v = 0; }
};
int main() {
    Box* b = new Box();
    b->v = 7;
    printf("%d\n", b->v);
    delete b;
    return 0;
}
