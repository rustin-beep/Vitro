// @category: baseline
#include <stdio.h>
#include <string.h>

void strAssign(char T[], char chars[]) {
    int i = 0;
    while (chars[i] != '\0') {
        T[i] = chars[i];
        i++;
    }
    T[i] = '\0';
}

int strCompare(char S[], char T[]) {
    int i = 0;
    while (S[i] != '\0' && T[i] != '\0') {
        if (S[i] != T[i])
            return S[i] - T[i];
        i++;
    }
    return S[i] - T[i];
}

void subString(char Sub[], char S[], int pos, int len) {
    int j = 0;
    for (int i = pos; i < pos + len; i++) {
        Sub[j++] = S[i];
    }
    Sub[j] = '\0';
}

void concat(char T[], char S1[], char S2[]) {
    int i = 0, j = 0;
    while (S1[i] != '\0') {
        T[j++] = S1[i++];
    }
    i = 0;
    while (S2[i] != '\0') {
        T[j++] = S2[i++];
    }
    T[j] = '\0';
}

int main() {
    char s1[20], s2[20], sub[10], con[40];
    strAssign(s1, "hello");
    strAssign(s2, "world");
    printf("%d\n", strCompare(s1, s2));
    subString(sub, s1, 1, 3);
    printf("%s\n", sub);
    concat(con, s1, s2);
    printf("%s\n", con);
    return 0;
}

