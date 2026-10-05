// @category: baseline
#include <stdio.h>
int main() {
    char buf[64];
    sprintf(buf, "value=%d", 42);
    printf("%s\n", buf);
    return 0;
}
