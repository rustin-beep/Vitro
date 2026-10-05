#include <stdio.h>
#include <string.h>

int canConstruct(char* ransomNote, char* magazine) {
    int count[26] = {0};
    for (int i = 0; magazine[i] != '\0'; i++) {
        count[magazine[i] - 'a']++;
    }
    for (int i = 0; ransomNote[i] != '\0'; i++) {
        if (--count[ransomNote[i] - 'a'] < 0) return 0;
    }
    return 1;
}

int main(void) {
    printf("%d\n", canConstruct("a", "b"));
    printf("%d\n", canConstruct("aa", "ab"));
    printf("%d\n", canConstruct("aa", "aab"));
    return 0;
}
