#include <stdio.h>

struct S {
    int* p;
};

int main() {
    int a[3] = {10, 20, 30};
    struct S s;
    s.p = a;
    s.p += 2;
    printf("%d\n", *s.p);
    return 0;
}
