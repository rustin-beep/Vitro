#include <stdio.h>

int main() {
    char buf[10] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9};
    void* p = buf;
    p += 3;
    printf("%d\n", *(char*)p);
    p -= 2;
    printf("%d\n", *(char*)p);
    return 0;
}
