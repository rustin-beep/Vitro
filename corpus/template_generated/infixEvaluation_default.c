// @category: baseline
#include <stdio.h>
#include <ctype.h>
#define MAX 100

int opStack[MAX];
int opTop = -1;
int valStack[MAX];
int valTop = -1;

int precedence(char op) {
    if (op == '+' || op == '-') return 1;
    if (op == '*' || op == '/') return 2;
    return 0;
}

void pushOp(char c) { opStack[++opTop] = c; }
char popOp() { return opStack[opTop--]; }
void pushVal(int v) { valStack[++valTop] = v; }
int popVal() { return valStack[valTop--]; }

void applyOp() {
    char op = popOp();
    int b = popVal();
    int a = popVal();
    switch (op) {
        case '+': pushVal(a + b); break;
        case '-': pushVal(a - b); break;
        case '*': pushVal(a * b); break;
        case '/': pushVal(a / b); break;
    }
}

int evaluate(char expr[]) {
    int i = 0;
    while (expr[i] != '\0') {
        if (expr[i] == ' ') {
            i++;
            continue;
        }
        if (isdigit(expr[i])) {
            int val = 0;
            while (isdigit(expr[i])) {
                val = val * 10 + (expr[i] - '0');
                i++;
            }
            pushVal(val);
            continue;
        }
        if (expr[i] == '(') {
            pushOp(expr[i]);
        } else if (expr[i] == ')') {
            while (opTop != -1 && opStack[opTop] != '(')
                applyOp();
            popOp();
        } else {
            while (opTop != -1 && precedence(opStack[opTop]) >= precedence(expr[i]))
                applyOp();
            pushOp(expr[i]);
        }
        i++;
    }
    while (opTop != -1)
        applyOp();
    return popVal();
}

int main() {
    char expr[] = "3 + 5 * 2 - 8 / 4";
    printf("%d\n", evaluate(expr));
    return 0;
}

