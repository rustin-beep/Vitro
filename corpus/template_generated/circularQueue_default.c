// @category: baseline
#include <stdio.h>
#define MAXSIZE 5

struct CircularQueue {
    int data[MAXSIZE];
    int front;
    int rear;
};

void init(struct CircularQueue* q) {
    q->front = 0;
    q->rear = 0;
}

int isEmpty(struct CircularQueue* q) {
    return q->front == q->rear;
}

int isFull(struct CircularQueue* q) {
    return (q->rear + 1) % MAXSIZE == q->front;
}

void enqueue(struct CircularQueue* q, int x) {
    if (isFull(q)) return;
    q->data[q->rear] = x;
    q->rear = (q->rear + 1) % MAXSIZE;
}

int dequeue(struct CircularQueue* q) {
    if (isEmpty(q)) return -1;
    int x = q->data[q->front];
    q->front = (q->front + 1) % MAXSIZE;
    return x;
}

int main() {
    struct CircularQueue q;
    init(&q);
    enqueue(&q, 10);
    enqueue(&q, 20);
    enqueue(&q, 30);
    printf("%d ", dequeue(&q));
    printf("%d ", dequeue(&q));
    printf("%d\n", dequeue(&q));
    return 0;
}

