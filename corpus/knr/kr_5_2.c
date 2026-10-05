#include <stdio.h>
#include <ctype.h>
#define EOF -1
int getfloat(float *pn) {
    int c, sign;
    float power;
    while ((c = getchar()) == ' ' || c == '\t' || c == '\n')
        ;
    if (!isdigit(c) && c != EOF && c != '+' && c != '-' && c != '.') {
        ungetc(c, stdin);
        return 0;
    }
    sign = (c == '-') ? -1 : 1;
    if (c == '+' || c == '-')
        c = getchar();
    for (*pn = 0.0; isdigit(c); c = getchar())
        *pn = 10.0 * *pn + (c - '0');
    if (c == '.')
        c = getchar();
    for (power = 1.0; isdigit(c); c = getchar()) {
        *pn = 10.0 * *pn + (c - '0');
        power *= 10.0;
    }
    *pn *= sign / power;
    if (c != EOF)
        ungetc(c, stdin);
    return c;
}
int main() {
    float f;
    while (getfloat(&f) != EOF)
        printf("%.3f\n", f);
    return 0;
}
