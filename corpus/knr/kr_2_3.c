#include <stdio.h>
int htoi(char s[]) {
    int i, n;
    n = 0;
    for (i = 0; s[i] != '\0'; i++) {
        int c = s[i];
        if (c >= '0' && c <= '9')
            n = 16 * n + (c - '0');
        else if (c >= 'a' && c <= 'f')
            n = 16 * n + (c - 'a' + 10);
        else if (c >= 'A' && c <= 'F')
            n = 16 * n + (c - 'A' + 10);
    }
    return n;
}
int main() {
    printf("%d\n", htoi("0x1A"));
    printf("%d\n", htoi("FF"));
    printf("%d\n", htoi("0"));
    return 0;
}
