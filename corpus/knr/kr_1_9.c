#include <stdio.h>
#define EOF -1
int main() {
    int c, lastc;
    lastc = 0;
    while ((c = getchar()) != EOF) {
        if (c != ' ' || lastc != ' ') {
            putchar(c);
        }
        lastc = c;
    }
    return 0;
}
