#include <stdio.h>
void strncpyy(char *s, char *t, int n) {
    while (*t && n-- > 0)
        *s++ = *t++;
    while (n-- > 0)
        *s++ = '\0';
}
void strncatt(char *s, char *t, int n) {
    while (*s)
        s++;
    while (*t && n-- > 0)
        *s++ = *t++;
    *s = '\0';
}
int strncmpp(char *s, char *t, int n) {
    for (; *s == *t; s++, t++)
        if (*s == '\0' || --n <= 0)
            return 0;
    return *s - *t;
}
int main() {
    char s[100] = "hello";
    strncatt(s, " world", 3);
    printf("%s\n", s);
    printf("%d\n", strncmpp("abc", "abd", 2));
    return 0;
}
