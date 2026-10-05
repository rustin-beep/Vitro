#include <stdio.h>
int value(char c) {
    if (c == 'I') return 1;
    if (c == 'V') return 5;
    if (c == 'X') return 10;
    if (c == 'L') return 50;
    if (c == 'C') return 100;
    if (c == 'D') return 500;
    return 1000;
}
int romanToInt(char* s) {
    int r = 0;
    for (int i = 0; s[i]; i++) {
        int v = value(s[i]);
        if (s[i+1] && v < value(s[i+1])) r = r - v;
        else r = r + v;
    }
    return r;
}
int main() {
    printf("%d\n", romanToInt("MCMXCIV"));
    return 0;
}
