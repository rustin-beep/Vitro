#include <stdio.h>
template<class T>
class Stack {
    T data[100];
    int top;
public:
    Stack() { top = 0; }
    void push(T x) { data[top++] = x; }
    T pop() { return data[--top]; }
    int size() { return top; }
};
int main() {
    Stack<int> s;
    s.push(1);
    s.push(2);
    s.push(3);
    printf("%d\n", s.pop());
    printf("%d\n", s.pop());
    printf("%d\n", s.size());
    return 0;
}
