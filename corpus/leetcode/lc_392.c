#include <stdio.h>
#include <string.h>

int isSubsequence(char* s, char* t) {
    int i = 0, j = 0;
    int n = strlen(s), m = strlen(t);
    while (i < n && j < m) {
        if (s[i] == t[j]) i++;
        j++;
    }
    return i == n;
}

int main(void) {
    printf("%d\n", isSubsequence("abc", "ahbgdc"));
    printf("%d\n", isSubsequence("axc", "ahbgdc"));
    return 0;
}
