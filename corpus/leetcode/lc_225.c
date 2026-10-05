#include <stdio.h>
#include <stdlib.h>

typedef struct {
    int q[100];
    int head;
    int tail;
    int size;
} MyStack;

MyStack* myStackCreate() {
    MyStack* s = (MyStack*)malloc(sizeof(MyStack));
    s->head = 0;
    s->tail = 0;
    s->size = 0;
    return s;
}

void myStackPush(MyStack* obj, int x) {
    int n = obj->size;
    obj->q[obj->tail] = x;
    obj->tail = (obj->tail + 1) % 100;
    obj->size++;
    for (int i = 0; i < n; i++) {
        int v = obj->q[obj->head];
        obj->head = (obj->head + 1) % 100;
        obj->q[obj->tail] = v;
        obj->tail = (obj->tail + 1) % 100;
    }
}

int myStackPop(MyStack* obj) {
    int v = obj->q[obj->head];
    obj->head = (obj->head + 1) % 100;
    obj->size--;
    return v;
}

int myStackTop(MyStack* obj) {
    return obj->q[obj->head];
}

int myStackEmpty(MyStack* obj) {
    return obj->size == 0;
}

void myStackFree(MyStack* obj) {
    free(obj);
}

int main() {
    MyStack* s = myStackCreate();
    myStackPush(s, 1);
    myStackPush(s, 2);
    printf("%d\n", myStackTop(s));
    printf("%d\n", myStackPop(s));
    printf("%d\n", myStackEmpty(s));
    myStackFree(s);
    return 0;
}
