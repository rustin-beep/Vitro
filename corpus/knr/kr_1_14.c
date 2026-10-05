#include <stdio.h>
#define EOF -1
int main() {
    int c;
    int freq[26];
    for (int i = 0; i < 26; i++) freq[i] = 0;
    while ((c = getchar()) != EOF) {
        if (c >= 'a' && c <= 'z') freq[c - 'a']++;
    }
    for (int i = 0; i < 26; i++) {
        putchar('a' + i);
        putchar(':');
        for (int j = 0; j < freq[i]; j++) putchar('*');
        putchar('\n');
    }
    return 0;
}
