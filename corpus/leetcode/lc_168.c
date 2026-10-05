#include <stdio.h>

void convertToTitle(int columnNumber, char* out) {
    int i = 0;
    while (columnNumber > 0) {
        columnNumber--;
        out[i++] = columnNumber % 26 + 'A';
        columnNumber /= 26;
    }
    out[i] = '\0';
    int left = 0, right = i - 1;
    while (left < right) {
        char t = out[left];
        out[left] = out[right];
        out[right] = t;
        left++;
        right--;
    }
}

int main() {
    char buf[20];
    convertToTitle(1, buf);
    printf("%s\n", buf);
    convertToTitle(28, buf);
    printf("%s\n", buf);
    convertToTitle(701, buf);
    printf("%s\n", buf);
    return 0;
}
