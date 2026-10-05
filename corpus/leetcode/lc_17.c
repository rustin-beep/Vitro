#include <stdio.h>
#include <string.h>

char letters[10][5];
char result[1000][10];
int count;

void init() {
    strcpy(letters[2], "abc");
    strcpy(letters[3], "def");
    strcpy(letters[4], "ghi");
    strcpy(letters[5], "jkl");
    strcpy(letters[6], "mno");
    strcpy(letters[7], "pqrs");
    strcpy(letters[8], "tuv");
    strcpy(letters[9], "wxyz");
}

void backtrack(char* digits, int pos, char* current, int curLen) {
    if (digits[pos] == '\0') {
        current[curLen] = '\0';
        int i = 0;
        while (current[i] != '\0') {
            result[count][i] = current[i];
            i++;
        }
        result[count][i] = '\0';
        count++;
        return;
    }
    int d = digits[pos] - '0';
    char* s = letters[d];
    for (int i = 0; s[i] != '\0'; i++) {
        current[curLen] = s[i];
        backtrack(digits, pos + 1, current, curLen + 1);
    }
}

int main() {
    init();
    char digits[] = "23";
    char current[10];
    count = 0;
    backtrack(digits, 0, current, 0);
    printf("%d\n", count);
    for (int i = 0; i < count; i++) {
        printf("%s\n", result[i]);
    }
    return 0;
}
