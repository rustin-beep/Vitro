#include <stdio.h>
#include <string.h>

int strStr(char* haystack, char* needle) {
    int hlen = strlen(haystack);
    int nlen = strlen(needle);
    if (nlen == 0) return 0;
    for (int i = 0; i <= hlen - nlen; i++) {
        int j = 0;
        while (j < nlen && haystack[i + j] == needle[j]) {
            j++;
        }
        if (j == nlen) return i;
    }
    return -1;
}

int main() {
    printf("%d\n", strStr("hello", "ll"));
    printf("%d\n", strStr("aaaaa", "bba"));
    printf("%d\n", strStr("", ""));
    return 0;
}
