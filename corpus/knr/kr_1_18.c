#include <stdio.h>
#define EOF -1
#define MAXLINE 100
int getline(char s[], int lim) {
    int c, i;
    for (i = 0; i < lim - 1 && (c = getchar()) != EOF && c != '\n'; ++i)
        s[i] = c;
    if (c == '\n') {
        s[i] = c;
        ++i;
    }
    s[i] = '\0';
    return i;
}
int main() {
    int len;
    char line[MAXLINE];
    while ((len = getline(line, MAXLINE)) > 0) {
        int end = len - 1;
        while (end >= 0 && (line[end] == ' ' || line[end] == '\t' || line[end] == '\n'))
            --end;
        if (end >= 0) {
            line[end + 1] = '\n';
            line[end + 2] = '\0';
            printf("%s", line);
        }
    }
    return 0;
}
