#include <stdio.h>
#include <string.h>

void reverseString(char s[]) {
    int len = strlen(s);
    for (int i = 0; i < len / 2; i++) {
        char t = s[i];
        s[i] = s[len - 1 - i];
        s[len - 1 - i] = t;
    }
}

int main() {
    char s[32] = "algorithm";
    reverseString(s);
    printf("%s\n", s);
    return 0;
}
