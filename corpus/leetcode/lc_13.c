#include <stdio.h>
#include <string.h>

int value(char c) {
    switch (c) {
        case 'I': return 1;
        case 'V': return 5;
        case 'X': return 10;
        case 'L': return 50;
        case 'C': return 100;
        case 'D': return 500;
        case 'M': return 1000;
    }
    return 0;
}

int romanToInt(char* s) {
    int total = 0;
    int len = strlen(s);
    for (int i = 0; i < len; i++) {
        int v = value(s[i]);
        if (i + 1 < len && v < value(s[i + 1])) {
            total -= v;
        } else {
            total += v;
        }
    }
    return total;
}

int main() {
    printf("%d\n", romanToInt("III"));
    printf("%d\n", romanToInt("LVIII"));
    printf("%d\n", romanToInt("MCMXCIV"));
    return 0;
}
