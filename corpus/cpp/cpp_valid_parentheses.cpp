#include <stdio.h>
int isValid(char* s) {
    char st[100];
    int top = -1;
    for (int i = 0; s[i]; i++) {
        char c = s[i];
        if (c == '(' || c == '[' || c == '{') st[++top] = c;
        else {
            if (top < 0) return 0;
            char o = st[top--];
            if ((c == ')' && o != '(') || (c == ']' && o != '[') || (c == '}' && o != '{')) return 0;
        }
    }
    return top == -1;
}
int main() {
    printf("%d\n", isValid("()[]{}"));
    printf("%d\n", isValid("(]"));
    return 0;
}
