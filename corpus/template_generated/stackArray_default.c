// @category: baseline
#include <stdio.h>

int stack[100];
int top = -1;

void push(int x) {
    stack[++top] = x;
}

int pop() {
    if (top < 0) return -1;
    return stack[top--];
}

int main() {
    push(10);
    push(20);
    push(30);
    printf("%d ", pop());
    printf("%d ", pop());
    printf("%d\n", pop());
    return 0;
}

