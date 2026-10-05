#include <stdio.h>

struct S {
    int x;
    char y;
};

int main() {
    struct S a[2] = {{10, 'a'}, {20, 'b'}};
    struct S* p = a;
    p += 1;
    printf("%d\n", p->x);
    return 0;
}
