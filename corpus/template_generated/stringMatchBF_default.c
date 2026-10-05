// @category: baseline
#include <stdio.h>
#include <string.h>

int indexBF(char S[], char T[], int pos) {
    int i = pos;
    int j = 0;
    int lenS = strlen(S);
    int lenT = strlen(T);
    while (i < lenS && j < lenT) {
        if (S[i] == T[j]) {
            i++;
            j++;
        } else {
            i = i - j + 1;
            j = 0;
        }
    }
    if (j >= lenT) return i - lenT;
    else return -1;
}

int main() {
    char S[] = "ababcabcacbab";
    char T[] = "abcac";
    int pos = indexBF(S, T, 0);
    printf("%d\n", pos);
    return 0;
}

