#include <stdio.h>
#include <stdio.h>
#include <string.h>

int isIsomorphic(char* s, char* t) {
    if (strlen(s) != strlen(t)) return 0;
    int mapS[256] = {0};
    int mapT[256] = {0};
    int n = strlen(s);
    for (int i = 0; i < n; i++) {
        unsigned char cs = (unsigned char)s[i];
        unsigned char ct = (unsigned char)t[i];
        if (mapS[cs] != mapT[ct]) return 0;
        mapS[cs] = i + 1;
        mapT[ct] = i + 1;
    }
    return 1;
}

int main(void) {
    printf("%d\n", isIsomorphic("egg", "add"));
    printf("%d\n", isIsomorphic("foo", "bar"));
    printf("%d\n", isIsomorphic("paper", "title"));
    return 0;
}
