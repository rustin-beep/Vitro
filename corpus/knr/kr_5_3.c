#include <stdio.h>
void strcatt(char *s, char *t) {
    while (*s)
        s++;
    while ((*s++ = *t++))
        ;
}
int main() {
    char s[100] = "hello ";
    strcatt(s, "world");
    printf("%s\n", s);
    return 0;
}
