#include <stdio.h>
#include <string.h>

int lengthOfLongestSubstring(char* s) {
    int n = strlen(s);
    int max_len = 0;
    int start = 0;
    int map[256];
    for (int i = 0; i < 256; i++) {
        map[i] = -1;
    }
    for (int i = 0; i < n; i++) {
        unsigned char c = s[i];
        if (map[c] >= start) {
            start = map[c] + 1;
        }
        map[c] = i;
        int len = i - start + 1;
        if (len > max_len) {
            max_len = len;
        }
    }
    return max_len;
}

int main() {
    printf("%d\n", lengthOfLongestSubstring("abcabcbb"));
    printf("%d\n", lengthOfLongestSubstring("bbbbb"));
    printf("%d\n", lengthOfLongestSubstring("pwwkew"));
    printf("%d\n", lengthOfLongestSubstring(""));
    printf("%d\n", lengthOfLongestSubstring("dvdf"));
    return 0;
}
