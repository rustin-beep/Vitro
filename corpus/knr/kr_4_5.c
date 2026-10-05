
double myatof(char s[]) {
    double val, power;
    int i, sign;
    for (i = 0; s[i] == ' ' || s[i] == '\t' || s[i] == '\n'; i++)
        ;
    sign = (s[i] == '-') ? -1 : 1;
    if (s[i] == '+' || s[i] == '-')
        i++;
    for (val = 0.0; s[i] >= '0' && s[i] <= '9'; i++)
        val = 10.0 * val + (s[i] - '0');
    if (s[i] == '.')
        i++;
    for (power = 1.0; s[i] >= '0' && s[i] <= '9'; i++) {
        val = 10.0 * val + (s[i] - '0');
        power *= 10.0;
    }
    return sign * val / power;
}
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#define EOF -1
#define MAXOP 100
#define NUMBER '0'
int getop(char s[]);
void push(double f);
double pop(void);
int main() {
    int type;
    double op2;
    char s[MAXOP];
    while ((type = getop(s)) != EOF) {
        switch (type) {
        case NUMBER: push(myatof(s)); break;
        case '+': push(pop() + pop()); break;
        case '*': push(pop() * pop()); break;
        case '-': op2 = pop(); push(pop() - op2); break;
        case '/': op2 = pop(); if (op2 != 0.0) push(pop() / op2); break;
        case 's': push(sin(pop())); break;
        case 'e': push(exp(pop())); break;
        case 'p': op2 = pop(); push(pow(pop(), op2)); break;
        case '\n': printf("%.8g\n", pop()); break;
        default: printf("error: unknown command %s\n", s); break;
        }
    }
    return 0;
}
#define MAXVAL 100
int sp = 0;
double val[MAXVAL];
void push(double f) { if (sp < MAXVAL) val[sp++] = f; }
double pop(void) { if (sp > 0) return val[--sp]; else return 0.0; }
int getch(void);
void ungetch(int);
int getop(char s[]) {
    int i, c;
    while ((s[0] = c = getch()) == ' ' || c == '\t')
        ;
    s[1] = '\0';
    if (!(c >= '0' && c <= '9') && c != '.')
        return c;
    i = 0;
    if (c >= '0' && c <= '9')
        while ((s[++i] = c = getch()) >= '0' && c <= '9')
            ;
    if (c == '.')
        while ((s[++i] = c = getch()) >= '0' && c <= '9')
            ;
    s[i] = '\0';
    if (c != EOF)
        ungetch(c);
    return NUMBER;
}
#define BUFSIZE 100
char buf[BUFSIZE];
int bufp = 0;
int getch(void) { if (bufp > 0) return buf[--bufp]; else return getchar(); }
void ungetch(int c) { if (bufp < BUFSIZE) buf[bufp++] = c; }
