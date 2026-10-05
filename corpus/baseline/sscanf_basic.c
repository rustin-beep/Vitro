// @category: baseline
#include <stdio.h>
int main() {
    int a, b;
    sscanf("10 20", "%d %d", &a, &b);
    printf("%d %d\n", a, b);
    return 0;
}
