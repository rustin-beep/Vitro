#include <stdio.h>
#include <string.h>
#define EOF -1
#define MAXLINE 100
int getlinee(char *s, int lim) {
    int c;
    char *p = s;
    while (--lim > 0 && (c = getchar()) != EOF && c != '\n')
        *p++ = c;
    if (c == '\n') *p++ = c;
    *p = '\0';
    return p - s;
}
int strindexx(char *s, char *t) {
    char *p, *q, *r;
    for (p = s; *p; p++) {
        for (q = p, r = t; *r && *q == *r; q++, r++)
            ;
        if (*r == '\0') return p - s;
    }
    return -1;
}
int main() {
    char line[MAXLINE];
    char *pattern = "the";
    while (getlinee(line, MAXLINE) > 0)
        if (strindexx(line, pattern) >= 0)
            printf("%s", line);
    return 0;
}
