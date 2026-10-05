#include <stdio.h>
#include <string.h>

int need[128];
int have[128];

int minWindow(char* s, char* t) {
    int need_count = 0;
    for (int i = 0; t[i]; i++) {
        if (need[(unsigned char)t[i]] == 0) {
            need_count++;
        }
        need[(unsigned char)t[i]]++;
    }
    int formed = 0;
    int left = 0;
    int min_len = 100000;
    for (int right = 0; s[right]; right++) {
        char c = s[right];
        have[(unsigned char)c]++;
        if (have[(unsigned char)c] == need[(unsigned char)c]) {
            formed++;
        }
        while (formed == need_count && left <= right) {
            int len = right - left + 1;
            if (len < min_len) {
                min_len = len;
            }
            char lc = s[left];
            have[(unsigned char)lc]--;
            if (have[(unsigned char)lc] < need[(unsigned char)lc]) {
                formed--;
            }
            left++;
        }
    }
    return min_len == 100000 ? 0 : min_len;
}

int main() {
    printf("%d\n", minWindow("ADOBECODEBANC", "ABC"));
    printf("%d\n", minWindow("a", "a"));
    printf("%d\n", minWindow("a", "aa"));

    return 0;
}
