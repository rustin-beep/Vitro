#include <stdio.h>
template<class T>
class Box {
public:
    T v;
    Box() { v = 0; }
};
int main() {
    Box<int> b;
    b.v = 99;
    printf("%d\n", b.v);
    return 0;
}
