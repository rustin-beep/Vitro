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

void getNextVal(char T[], int nextval[]) {
    int next[20];
    getNext(T, next);
    int lenT = strlen(T);
    nextval[0] = -1;
    for (int j = 1; j < lenT; j++) {
        if (T[j] == T[next[j]])
            nextval[j] = nextval[next[j]];
        else
            nextval[j] = next[j];
    }
}

int main() {
    char T[] = "ababaaaba";
    int nextval[20];
    getNextVal(T, nextval);
    int lenT = strlen(T);
    for (int i = 0; i < lenT; i++)
        printf("%d ", nextval[i]);
    printf("\n");
    return 0;
}

