#include <stdio.h>
#define EOF -1
#define IN 1
#define OUT 0
#define MAXLEN 10
int main() {
    int c, state, len;
    int lengths[MAXLEN];
    for (int i = 0; i < MAXLEN; i++) lengths[i] = 0;
    state = OUT;
    len = 0;
    while ((c = getchar()) != EOF) {
        if (c == ' ' || c == '\n' || c == '\t') {
            if (state == IN) {
                if (len < MAXLEN) lengths[len]++;
                len = 0;
            }
            state = OUT;
        } else {
            state = IN;
            ++len;
        }
    }
    for (int i = 1; i < MAXLEN; i++) {
        printf("%2d: ", i);
        for (int j = 0; j < lengths[i]; j++) putchar('*');
        putchar('\n');
    }
    return 0;
}
