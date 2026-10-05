#include <stdio.h>
int myatoi(char s[]) {
    int i, n;
    n = 0;
    for (i = 0; s[i] >= '0' && s[i] <= '9'; i++)
        n = 10 * n + (s[i] - '0');
    return n;
}
int main() {
    printf("%d\n", myatoi("12345"));
    printf("%d\n", myatoi("9876"));
    return 0;
}
