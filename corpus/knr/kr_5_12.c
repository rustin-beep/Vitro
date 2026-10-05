#include <stdio.h>
#define MAXLINE 100
#define TABSTOP 4
void entab(char *s) {
    int i, j, spaces;
    char out[MAXLINE];
    i = j = 0;
    while (s[i]) {
        if (s[i] == ' ') {
            spaces = 0;
            while (s[i] == ' ') {
                spaces++;
                i++;
            }
            while (spaces >= TABSTOP) {
                out[j++] = '\t';
                spaces -= TABSTOP;
            }
            while (spaces-- > 0)
                out[j++] = ' ';
        } else {
            out[j++] = s[i++];
        }
    }
    out[j] = '\0';
    printf("%s\n", out);
}
int main() {
    entab("a    b    c");
    return 0;
}
