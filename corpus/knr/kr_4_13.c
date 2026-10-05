#include <stdio.h>
void reverse(char s[], int i, int len) {
    int c, j;
    j = len - (i + 1);
    if (i < j) {
        c = s[i];
        s[i] = s[j];
        s[j] = c;
        reverse(s, ++i, len);
    }
}
int main() {
    char s[] = "abcdef";
    int len = 0;
    while (s[len] != '\0') len++;
    reverse(s, 0, len);
    printf("%s\n", s);
    return 0;
}
