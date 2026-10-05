#include <stdio.h>
class Point {
public:
    int x;
    int y;
    Point(int a, int b) : x(a), y(b) {}
    int sum() { return x + y; }
};
int main() {
    Point p(3, 4);
    printf("%d %d\n", p.x, p.y);
    printf("%d\n", p.sum());
    return 0;
}
