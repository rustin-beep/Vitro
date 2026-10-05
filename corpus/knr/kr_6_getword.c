#include <stdio.h>
#include <ctype.h>
int getword(char* word, int lim) {
    int c;
    char* w = word;
    while ((c = getchar()) != EOF && isspace(c))
        ;
    if (c != EOF)
        *w++ = c;
    if (!isalpha(c)) {
        *w = '\0';
        return c;
    }
    for (; --lim > 0; w++) {
        *w = getchar();
        if (!isalnum(*w)) {
            ungetc(*w, stdin);
            break;
        }
    }
    *w = '\0';
    return word[0];
}
int main() {
    char word[100];
    int count = 0;
    while (getword(word, 100) != EOF) {
        if (isalpha(word[0])) {
            printf("%s\n", word);
            count++;
        }
    }
    printf("%d\n", count);
    return 0;
}
