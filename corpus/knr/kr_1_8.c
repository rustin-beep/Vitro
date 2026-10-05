#include <stdio.h>
#define EOF -1
int main() {
    int c, nl, nt, nb;
    nl = nt = nb = 0;
    while ((c = getchar()) != EOF) {
        if (c == ' ') ++nb;
        if (c == '\t') ++nt;
        if (c == '\n') ++nl;
    }
    printf("%d %d %d\n", nb, nt, nl);
    return 0;
}
