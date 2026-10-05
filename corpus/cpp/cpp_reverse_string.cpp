#include <stdio.h>
void reverseString(char* s, int sSize) {
    int l = 0, r = sSize - 1;
    while (l < r) { char t = s[l]; s[l] = s[r]; s[r] = t; l++; r--; }
}
int main() {
    char s[] = "hello";
    reverseString(s, 5);
    printf("%s\n", s);
    return 0;
}
