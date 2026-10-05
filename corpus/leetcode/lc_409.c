#include <stdio.h>
#include <string.h>

int longestPalindrome(char* s) {
    int count[52] = {0};
    for (int i = 0; s[i] != '\0'; i++) {
        char c = s[i];
        if (c >= 'a' && c <= 'z') count[c - 'a']++;
        else count[c - 'A' + 26]++;
    }
    int len = 0, odd = 0;
    for (int i = 0; i < 52; i++) {
        len += count[i] / 2 * 2;
        if (count[i] % 2 == 1) odd = 1;
    }
    return len + odd;
}

int main(void) {
    printf("%d\n", longestPalindrome("abccccdd"));
    printf("%d\n", longestPalindrome("a"));
    printf("%d\n", longestPalindrome("bb"));
    return 0;
}
