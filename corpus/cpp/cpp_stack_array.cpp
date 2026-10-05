#include <stdio.h>
class Stack {
    int a[100];
    int top;
public:
    Stack() { top = -1; }
    void push(int x) { a[++top] = x; }
    int pop() { return a[top--]; }
    int size() { return top + 1; }
};
int main() {
    Stack s;
    s.push(1);
    s.push(2);
    s.push(3);
    while (s.size() > 0) printf("%d\n", s.pop());
    return 0;
}
