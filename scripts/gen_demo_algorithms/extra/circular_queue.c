#include <stdio.h>

#define SIZE 5

struct CircularQueue {
    int data[SIZE];
    int front;
    int rear;
};

int circularQueueEmpty(struct CircularQueue* q) {
    return q->front == q->rear;
}

int circularQueuePush(struct CircularQueue* q, int x) {
    if ((q->rear + 1) % SIZE == q->front) return 0;
    q->data[q->rear] = x;
    q->rear = (q->rear + 1) % SIZE;
    return 1;
}

int circularQueuePop(struct CircularQueue* q) {
    if (circularQueueEmpty(q)) return -1;
    int v = q->data[q->front];
    q->front = (q->front + 1) % SIZE;
    return v;
}

int main() {
    struct CircularQueue q = { {0}, 0, 0 };
    circularQueuePush(&q, 10);
    circularQueuePush(&q, 20);
    circularQueuePush(&q, 30);
    printf("%d %d\n", circularQueuePop(&q), circularQueuePop(&q));
    return 0;
}
