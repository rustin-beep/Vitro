#include <stdio.h>
int atoii(char *s) {
    int n = 0;
    while (*s >= '0' && *s <= '9')
        n = 10 * n + (*s++ - '0');
    return n;
}
void itoaa(int n, char *s) {
    int sign;
    char *p = s;
    if ((sign = n) < 0)
        n = -n;
    do {
        *p++ = n % 10 + '0';
    } while ((n /= 10) > 0);
    if (sign < 0)
        *p++ = '-';
    *p = '\0';
    char *q = s;
    char tmp;
    for (p--; q < p; q++, p--) {
        tmp = *q; *q = *p; *p = tmp;
    }
}
int strindexx(char *s, char *t) {
    char *p, *q, *r;
    for (p = s; *p; p++) {
        for (q = p, r = t; *r && *q == *r; q++, r++)
            ;
        if (*r == '\0')
            return p - s;
    }
    return -1;
}
int main() {
    char s[100];
    printf("%d\n", atoii("12345"));
    itoaa(-987, s);
    printf("%s\n", s);
    printf("%d\n", strindexx("hello world", "world"));
    return 0;
}
