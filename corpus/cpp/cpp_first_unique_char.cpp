#include <stdio.h>
int firstUniqChar(char* s) {
    int cnt[26] = {0};
    for (int i = 0; s[i]; i++) cnt[s[i] - 'a']++;
    for (int i = 0; s[i]; i++) if (cnt[s[i] - 'a'] == 1) return i;
    return -1;
}
int main() {
    printf("%d\n", firstUniqChar("leetcode"));
    return 0;
}
