#include <stdio.h>
void itoa(int n, char s[], int w) {
    int i, sign;
    if ((sign = n) < 0)
        n = -n;
    i = 0;
    do {
        s[i++] = n % 10 + '0';
    } while ((n /= 10) > 0);
    if (sign < 0)
        s[i++] = '-';
    while (i < w)
        s[i++] = ' ';
    s[i] = '\0';
    int j, k;
    char temp;
    for (j = 0, k = i - 1; j < k; j++, k--) {
        temp = s[j]; s[j] = s[k]; s[k] = temp;
    }
}
int main() {
    char s[100];
    itoa(123, s, 6);
    printf("[%s]\n", s);
    itoa(-45, s, 6);
    printf("[%s]\n", s);
    return 0;
}
