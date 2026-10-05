// @category: baseline
#include <stdio.h>
#define MAX 100

int match(char expr[]) {
    char stack[MAX];
    int top = -1;
    for (int i = 0; expr[i] != '\0'; i++) {
        if (expr[i] == '(' || expr[i] == '[' || expr[i] == '{') {
            stack[++top] = expr[i];
        } else if (expr[i] == ')' || expr[i] == ']' || expr[i] == '}') {
            if (top == -1) return 0;
            char left = stack[top--];
            if ((expr[i] == ')' && left != '(') ||
                (expr[i] == ']' && left != '[') ||
                (expr[i] == '}' && left != '{'))
                return 0;
        }
    }
    return top == -1;
}

int main() {
    char expr[] = "{[()]}";
    if (match(expr))
        printf("matched\n");
    else
        printf("not matched\n");
    return 0;
}

