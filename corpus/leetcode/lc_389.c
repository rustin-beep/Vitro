#include <stdio.h>

char findTheDifference(char* s, char* t) {
    int sum = 0;
    while (*t) {
        sum += *t;
        t++;
    }
    while (*s) {
        sum -= *s;
        s++;
    }
    return (char)sum;
}

int main(void) {
    printf("%c\n", findTheDifference("abcd", "abcde"));
    printf("%c\n", findTheDifference("", "y"));
    return 0;
}
