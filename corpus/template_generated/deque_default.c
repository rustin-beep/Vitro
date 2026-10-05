// @category: baseline
#include <stdio.h>
#define MAXSIZE 10

struct Deque {
    int data[MAXSIZE];
    int front;
    int rear;
    int size;
};

void init(struct Deque* dq) {
    dq->front = 0;
    dq->rear = 0;
    dq->size = 0;
}

int isEmpty(struct Deque* dq) { return dq->size == 0; }
int isFull(struct Deque* dq) { return dq->size == MAXSIZE; }

void pushFront(struct Deque* dq, int x) {
    if (isFull(dq)) return;
    dq->front = (dq->front - 1 + MAXSIZE) % MAXSIZE;
    dq->data[dq->front] = x;
    dq->size++;
}

void pushRear(struct Deque* dq, int x) {
    if (isFull(dq)) return;
    dq->data[dq->rear] = x;
    dq->rear = (dq->rear + 1) % MAXSIZE;
    dq->size++;
}

int popFront(struct Deque* dq) {
    if (isEmpty(dq)) return -1;
    int x = dq->data[dq->front];
    dq->front = (dq->front + 1) % MAXSIZE;
    dq->size--;
    return x;
}

int popRear(struct Deque* dq) {
    if (isEmpty(dq)) return -1;
    dq->rear = (dq->rear - 1 + MAXSIZE) % MAXSIZE;
    int x = dq->data[dq->rear];
    dq->size--;
    return x;
}

int main() {
    struct Deque dq;
    init(&dq);
    pushRear(&dq, 10);
    pushRear(&dq, 20);
    pushFront(&dq, 5);
    printf("%d ", popFront(&dq));
    printf("%d ", popRear(&dq));
    printf("%d\n", popFront(&dq));
    return 0;
}

