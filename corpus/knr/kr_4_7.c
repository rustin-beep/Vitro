#include <stdio.h>
#define EOF -1
#define BUFSIZE 100
char buf[BUFSIZE];
int bufp = 0;
int getch(void) { if (bufp > 0) return buf[--bufp]; else return getchar(); }
void ungetch(int c) { if (bufp < BUFSIZE) buf[bufp++] = c; }
void ungets(char s[]) {
    int i;
    for (i = 0; s[i] != '\0'; i++)
        ;
    while (i > 0)
        ungetch(s[--i]);
}
int main() {
    char s[] = "hello";
    ungets(s);
    int c;
    while ((c = getch()) != '\n' && c != EOF)
        putchar(c);
    putchar('\n');
    return 0;
}
