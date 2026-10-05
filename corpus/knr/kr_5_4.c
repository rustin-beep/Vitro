#include <stdio.h>
int strend(char *s, char *t) {
    char *bs = s;
    char *bt = t;
    while (*s)
        s++;
    while (*t)
        t++;
    for (; *s == *t; s--, t--)
        if (t == bt || s == bs)
            break;
    if (*s == *t && t == bt && *s != '\0')
        return 1;
    else
        return 0;
}
int main() {
    printf("%d\n", strend("hello world", "world"));
    printf("%d\n", strend("hello world", "hello"));
    return 0;
}
