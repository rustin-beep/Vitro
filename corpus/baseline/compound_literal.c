// @category: baseline
#include <stdio.h>

struct S {
    int x;
    int y;
};

int main() {
    struct S s = (struct S){1, 2};
    int* p = &(int){5};
    int arr[3] = (int[]){10, 20, 30};
    printf("%d %d %d %d", s.x, *p, arr[1], ((struct S){.x=7}).x);
    return 0;
}
