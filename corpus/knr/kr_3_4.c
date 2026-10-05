#include <stdio.h>
#define INT_MIN -2147483648
void itoa(int n, char s[]) {
    int i, sign;
    unsigned un;
    if ((sign = n) < 0) {
        un = (unsigned)n;
        un = -un;
    } else
        un = n;
    i = 0;
    do {
        s[i++] = un % 10 + '0';
    } while ((un /= 10) > 0);
    if (sign < 0)
        s[i++] = '-';
    s[i] = '\0';
    int j, k;
    char temp;
    for (j = 0, k = i - 1; j < k; j++, k--) {
        temp = s[j]; s[j] = s[k]; s[k] = temp;
    }
}
int main() {
    char s[100];
    itoa(INT_MIN, s);
    printf("%s\n", s);
    itoa(12345, s);
    printf("%s\n", s);
    itoa(-9876, s);
    printf("%s\n", s);
    return 0;
}
