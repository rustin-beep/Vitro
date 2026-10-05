// @category: baseline
#include <stdio.h>
#include <stdlib.h>
int main() {
    int* p = calloc(3, sizeof(int));
    printf("%d %d %d\n", p[0], p[1], p[2]);
    free(p);
    return 0;
}
