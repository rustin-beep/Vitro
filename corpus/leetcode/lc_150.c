#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int evalRPN(char** tokens, int tokensSize) {
    int* stack = (int*)malloc(tokensSize * sizeof(int));
    int top = 0;
    for (int i = 0; i < tokensSize; i++) {
        char* t = tokens[i];
        if (strlen(t) == 1 && (t[0] == '+' || t[0] == '-' || t[0] == '*' || t[0] == '/')) {
            int b = stack[--top];
            int a = stack[--top];
            int c = 0;
            if (t[0] == '+') c = a + b;
            else if (t[0] == '-') c = a - b;
            else if (t[0] == '*') c = a * b;
            else c = a / b;
            stack[top++] = c;
        } else {
            stack[top++] = atoi(t);
        }
    }
    int res = stack[0];
    free(stack);
    return res;
}

int main(void) {
    char* t1[] = {"2","1","+","3","*"};
    printf("%d\n", evalRPN(t1, 5));
    char* t2[] = {"4","13","5","/","+"};
    printf("%d\n", evalRPN(t2, 5));
    char* t3[] = {"10","6","9","3","+","-11","*","/","*","17","+","5","+"};
    printf("%d\n", evalRPN(t3, 13));
    return 0;
}
