// @category: baseline
#include <stdio.h>
#include <string.h>

void getNext(char T[], int next[]) {
    int j = 0, k = -1;
    next[0] = -1;
    int lenT = strlen(T);
    while (j < lenT - 1) {
        if (k == -1 || T[j] == T[k]) {
            j++;
            k++;
            next[j] = k;
        } else {
            k = next[k];
        }
    }
}

int indexKMP(char S[], char T[], int pos) {
    int i = pos, j = 0;
    int next[20];
    getNext(T, next);
    int lenS = strlen(S);
    int lenT = strlen(T);
    while (i < lenS && j < lenT) {
        if (j == -1 || S[i] == T[j]) {
            i++;
            j++;
        } else {
            j = next[j];
        }
    }
    if (j >= lenT) return i - lenT;
    else return -1;
}

int main() {
    char S[] = "ababcabcacbab";
    char T[] = "abcac";
    int pos = indexKMP(S, T, 0);
    printf("%d\n", pos);
    return 0;
}

