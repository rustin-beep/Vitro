// @category: baseline
#include <stdio.h>
int main() {
    char buf[8];
    snprintf(buf, 8, "value=%d", 12345);
    printf("%s\n", buf);
    return 0;
}
