#include <stdio.h>
class Queue {
    int a[100];
    int head;
    int tail;
public:
    Queue() { head = 0; tail = 0; }
    void push(int x) { a[tail++] = x; }
    int pop() { return a[head++]; }
    int size() { return tail - head; }
};
int main() {
    Queue q;
    q.push(1);
    q.push(2);
    q.push(3);
    while (q.size() > 0) printf("%d\n", q.pop());
    return 0;
}
