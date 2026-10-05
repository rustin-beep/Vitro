#include <stdio.h>
#include <stdlib.h>

typedef struct {
    int data[10000];
    int minData[10000];
    int top;
} MinStack;

MinStack* minStackCreate() {
    MinStack* s = (MinStack*)malloc(sizeof(MinStack));
    s->top = -1;
    return s;
}

void minStackPush(MinStack* obj, int val) {
    obj->top++;
    obj->data[obj->top] = val;
    if (obj->top == 0) {
        obj->minData[obj->top] = val;
    } else {
        obj->minData[obj->top] = val < obj->minData[obj->top - 1] ? val : obj->minData[obj->top - 1];
    }
}

void minStackPop(MinStack* obj) {
    obj->top--;
}

int minStackTop(MinStack* obj) {
    return obj->data[obj->top];
}

int minStackGetMin(MinStack* obj) {
    return obj->minData[obj->top];
}

void minStackFree(MinStack* obj) {
    free(obj);
}

int main() {
    MinStack* s = minStackCreate();
    minStackPush(s, -2);
    minStackPush(s, 0);
    minStackPush(s, -3);
    printf("%d\n", minStackGetMin(s));
    minStackPop(s);
    printf("%d\n", minStackTop(s));
    printf("%d\n", minStackGetMin(s));
    minStackFree(s);
    return 0;
}
