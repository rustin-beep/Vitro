#include <stdio.h>
#define EOF -1
int main() {
    int c;
    c = getchar() != EOF;
    printf("%d\n", c);
    return 0;
}
