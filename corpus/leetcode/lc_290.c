#include <stdio.h>
#include <string.h>

int wordPattern(char* pattern, char** words, int wordsSize) {
    if ((int)strlen(pattern) != wordsSize) return 0;
    char map[26][64];
    int used[26] = {0};
    for (int i = 0; pattern[i]; i++) {
        int idx = pattern[i] - 'a';
        if (used[idx]) {
            if (strcmp(map[idx], words[i]) != 0) return 0;
        } else {
            for (int j = 0; j < 26; j++) {
                if (used[j] && strcmp(map[j], words[i]) == 0) return 0;
            }
            strcpy(map[idx], words[i]);
            used[idx] = 1;
        }
    }
    return 1;
}

int main(void) {
    char* w1[] = {"dog", "cat", "cat", "dog"};
    printf("%d\n", wordPattern("abba", w1, 4));
    char* w2[] = {"dog", "cat", "cat", "fish"};
    printf("%d\n", wordPattern("abba", w2, 4));
    char* w3[] = {"dog", "cat", "dog", "cat"};
    printf("%d\n", wordPattern("aaaa", w3, 4));
    char* w4[] = {"a", "b", "c", "d"};
    printf("%d\n", wordPattern("abcd", w4, 4));
    return 0;
}
