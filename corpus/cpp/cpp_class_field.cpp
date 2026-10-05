#include <stdio.h>
class Point {
public:
    int x, y;
    Point() { x = y = 0; }
};
int main() {
    Point p;
    p.x = 42;
    printf("%d\n", p.x);
    return 0;
}
