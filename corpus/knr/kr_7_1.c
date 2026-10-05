#include <stdio.h>
int main() {
    int c;
    while ((c = getchar()) != EOF) {
        if (c >= 'a' && c <= 'z')
            c = c - 'a' + 'A';
        putchar(c);
    }
    return 0;
}
