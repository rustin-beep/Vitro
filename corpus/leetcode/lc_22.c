#include <stdio.h>

char result[1000][20];
int count;

void backtrack(char* s, int open, int close, int n, int pos) {
    if (pos == 2 * n) {
        s[pos] = '\0';
        int i = 0;
        while (s[i] != '\0') {
            result[count][i] = s[i];
            i++;
        }
        result[count][i] = '\0';
        count++;
        return;
    }
    if (open < n) {
        s[pos] = '(';
        backtrack(s, open + 1, close, n, pos + 1);
    }
    if (close < open) {
        s[pos] = ')';
        backtrack(s, open, close + 1, n, pos + 1);
    }
}

int main() {
    char s[20];
    count = 0;
    backtrack(s, 0, 0, 3, 0);
    printf("%d\n", count);
    for (int i = 0; i < count; i++) {
        printf("%s\n", result[i]);
    }
    return 0;
}
