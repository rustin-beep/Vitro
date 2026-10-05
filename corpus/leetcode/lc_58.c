#include <stdio.h>
#include <string.h>

int lengthOfLastWord(char* s) {
    int len = strlen(s);
    int end = len - 1;
    while (end >= 0 && s[end] == ' ') end--;
    int start = end;
    while (start >= 0 && s[start] != ' ') start--;
    return end - start;
}

int main() {
    printf("%d\n", lengthOfLastWord("Hello World"));
    printf("%d\n", lengthOfLastWord("   fly me   to   the moon  "));
    printf("%d\n", lengthOfLastWord("luffy is still joyboy"));
    return 0;
}
