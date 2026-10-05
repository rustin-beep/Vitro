#include <stdio.h>
void itob(int n, char s[], int b) {
    int i, j, sign;
    char digits[] = "0123456789ABCDEF";
    if ((sign = n) < 0)
        n = -n;
    i = 0;
    do {
        s[i++] = digits[n % b];
    } while ((n /= b) > 0);
    if (sign < 0)
        s[i++] = '-';
    s[i] = '\0';
    char temp;
    for (j = 0, --i; j < i; j++, i--) {
        temp = s[j]; s[j] = s[i]; s[i] = temp;
    }
}
int main() {
    char s[100];
    itob(255, s, 16);
    printf("%s\n", s);
    itob(255, s, 8);
    printf("%s\n", s);
    itob(255, s, 2);
    printf("%s\n", s);
    return 0;
}
