#include <stdio.h>
#include <string.h>

int numDecodings(char* s) {
    int n = strlen(s);
    if (n == 0 || s[0] == '0') {
        return 0;
    }
    int prev2 = 1;
    int prev1 = 1;
    for (int i = 1; i < n; i++) {
        int current = 0;
        int one = s[i] - '0';
        if (one >= 1 && one <= 9) {
            current += prev1;
        }
        int two = (s[i - 1] - '0') * 10 + one;
        if (two >= 10 && two <= 26) {
            current += prev2;
        }
        if (current == 0) {
            return 0;
        }
        prev2 = prev1;
        prev1 = current;
    }
    return prev1;
}

int main() {
    printf("%d\n", numDecodings("12"));
    printf("%d\n", numDecodings("226"));
    printf("%d\n", numDecodings("0"));
    printf("%d\n", numDecodings("10"));
    printf("%d\n", numDecodings("27"));

    return 0;
}
