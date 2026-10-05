#include <stdio.h>
#include <stdlib.h>

typedef struct {
    int in[100];
    int out[100];
    int inTop;
    int outTop;
} MyQueue;

MyQueue* myQueueCreate() {
    MyQueue* q = (MyQueue*)malloc(sizeof(MyQueue));
    q->inTop = -1;
    q->outTop = -1;
    return q;
}

void myQueuePush(MyQueue* obj, int x) {
    obj->in[++obj->inTop] = x;
}

void move(MyQueue* obj) {
    if (obj->outTop < 0) {
        while (obj->inTop >= 0) {
            obj->outTop++;
            obj->out[obj->outTop] = obj->in[obj->inTop];
            obj->inTop--;
        }
    }
}

int myQueuePop(MyQueue* obj) {
    move(obj);
    int v = obj->out[obj->outTop];
    obj->outTop--;
    return v;
}

int myQueuePeek(MyQueue* obj) {
    move(obj);
    return obj->out[obj->outTop];
}

int myQueueEmpty(MyQueue* obj) {
    return obj->inTop < 0 && obj->outTop < 0;
}

void myQueueFree(MyQueue* obj) {
    free(obj);
}

int main() {
    MyQueue* q = myQueueCreate();
    myQueuePush(q, 1);
    myQueuePush(q, 2);
    printf("%d\n", myQueuePeek(q));
    printf("%d\n", myQueuePop(q));
    printf("%d\n", myQueueEmpty(q));
    myQueueFree(q);
    return 0;
}
