#include <stdio.h>

class Box {
public:
    int w, h;
    Box(int width = 1, int height = 2) {
        w = width;
        h = height;
    }
    int area(int scale = 1) {
        return w * h * scale;
    }
};

int add(int a, int b = 10, int c = 100) {
    return a + b + c;
}

int main() {
    Box b1;
    Box b2(3);
    Box b3(4, 5);

    printf("%d %d %d\n", b1.w, b1.h, b1.area());
    printf("%d %d %d\n", b2.w, b2.h, b2.area(2));
    printf("%d %d %d\n", b3.w, b3.h, b3.area(3));

    printf("%d\n", add(1));
    printf("%d\n", add(1, 2));
    printf("%d\n", add(1, 2, 3));

    return 0;
}
