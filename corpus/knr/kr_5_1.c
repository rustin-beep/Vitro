#include <stdio.h>
#include <ctype.h>
#define EOF -1
int getint(int *pn) {
    int c, sign;
    while ((c = getchar()) == ' ' || c == '\t' || c == '\n')
        ;
    if (!isdigit(c) && c != EOF && c != '+' && c != '-') {
        ungetc(c, stdin);
        return 0;
    }
    sign = (c == '-') ? -1 : 1;
    if (c == '+' || c == '-')
        c = getchar();
    for (*pn = 0; isdigit(c); c = getchar())
        *pn = 10 * *pn + (c - '0');
    *pn *= sign;
    if (c != EOF)
        ungetc(c, stdin);
    return c;
}
int main() {
    int n;
    while (getint(&n) != EOF)
        printf("%d\n", n);
    return 0;
}
