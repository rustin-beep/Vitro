#include <stdio.h>
#include <string.h>

int firstUniqChar(char* s) {
    int count[26] = {0};
    int len = strlen(s);
    for (int i = 0; i < len; i++) {
        count[s[i] - 'a']++;
    }
    for (int i = 0; i < len; i++) {
        if (count[s[i] - 'a'] == 1) return i;
    }
    return -1;
}

int main() {
    printf("%d\n", firstUniqChar("leetcode"));
    printf("%d\n", firstUniqChar("loveleetcode"));
    printf("%d\n", firstUniqChar("aabb"));
    return 0;
}
