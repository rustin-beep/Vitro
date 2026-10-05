// @category: baseline
#include <stdio.h>

int queue[100];
int front = 0, rear = 0;

void enqueue(int x) {
    queue[rear++] = x;
}

int dequeue() {
    if (front == rear) return -1;
    return queue[front++];
}

int main() {
    enqueue(10);
    enqueue(20);
    enqueue(30);
    printf("%d ", dequeue());
    printf("%d ", dequeue());
    printf("%d\n", dequeue());
    return 0;
}

