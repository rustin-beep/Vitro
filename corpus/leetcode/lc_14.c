#include <stdio.h>
#include <stdlib.h>
#include <string.h>

char* longestCommonPrefix(char** strs, int strsSize) {
    if (strsSize == 0) {
        char* empty = (char*)malloc(1);
        empty[0] = '\0';
        return empty;
    }
    int len = strlen(strs[0]);
    for (int i = 1; i < strsSize; i++) {
        int j = 0;
        while (j < len && strs[i][j] != '\0' && strs[0][j] == strs[i][j]) {
            j++;
        }
        len = j;
    }
    char* result = (char*)malloc(len + 1);
    for (int i = 0; i < len; i++) {
        result[i] = strs[0][i];
    }
    result[len] = '\0';
    return result;
}

int main() {
    char* strs1[] = {"flower", "flow", "flight"};
    char* r1 = longestCommonPrefix(strs1, 3);
    printf("%s\n", r1);
    free(r1);

    char* strs2[] = {"dog", "racecar", "car"};
    char* r2 = longestCommonPrefix(strs2, 3);
    printf("%s\n", r2);
    free(r2);

    return 0;
}
