#include <stdio.h>
char out[100];
char* longestCommonPrefix(char** strs, int strsSize) {
    if (strsSize == 0) { out[0] = '\0'; return out; }
    int i = 0;
    while (strs[0][i]) {
        for (int j = 1; j < strsSize; j++) if (strs[j][i] != strs[0][i]) { out[i] = '\0'; return out; }
        out[i] = strs[0][i];
        i++;
    }
    out[i] = '\0';
    return out;
}
int main() {
    char* strs[] = {"flower", "flow", "flight"};
    printf("%s\n", longestCommonPrefix(strs, 3));
    return 0;
}
