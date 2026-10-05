#include <stdio.h>
#include <stdlib.h>
#define EOF -1
#define MAXLINE 100
#define MAXLEN 100
#define DEFAULT 5
int readline(char *line, int max) {
    int c, i;
    for (i = 0; i < max - 1 && (c = getchar()) != EOF && c != '\n'; i++)
        line[i] = c;
    line[i] = '\0';
    return i;
}
int main() {
    char *lineptr[DEFAULT];
    int len, nlines = 0;
    char *p, line[MAXLINE];
    while ((len = readline(line, MAXLINE)) > 0) {
        if (nlines >= DEFAULT) break;
        if ((p = malloc(len + 1)) == NULL) return 1;
        strcpy(p, line);
        lineptr[nlines++] = p;
    }
    for (int i = 0; i < nlines; i++)
        printf("%s\n", lineptr[i]);
    for (int i = 0; i < nlines; i++)
        free(lineptr[i]);
    return 0;
}
