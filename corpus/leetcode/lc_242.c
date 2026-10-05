#include <stdio.h>

int isAnagram(char* s, char* t) {
    int count[26];
    for (int i = 0; i < 26; i++) count[i] = 0;
    for (int i = 0; s[i] != '\0'; i++) count[s[i] - 'a']++;
    for (int i = 0; t[i] != '\0'; i++) count[t[i] - 'a']--;
    for (int i = 0; i < 26; i++) {
        if (count[i] != 0) return 0;
    }
    return 1;
}

int main() {
    printf("%d\n", isAnagram("anagram", "nagaram"));
    printf("%d\n", isAnagram("rat", "car"));
    return 0;
}
