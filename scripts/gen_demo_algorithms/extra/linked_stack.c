#include <stdio.h>
#include <stdlib.h>

struct Node {
    int data;
    struct Node* next;
};

int linkedStackEmpty(struct Node* top) {
    return top == NULL;
}

struct Node* linkedStackPush(struct Node* top, int x) {
    struct Node* node = (struct Node*)malloc(sizeof(struct Node)); node->next = top;
    node->data = x;
    return node;
}

struct Node* linkedStackPop(struct Node* top, int* out) {
    if (linkedStackEmpty(top)) return top;
    struct Node* temp = top;
    *out = temp->data;
    top = temp->next;
    free(temp);
    return top;
}

int main() {
    struct Node* top = NULL;
    int v = 0;
    top = linkedStackPush(top, 10);
    top = linkedStackPush(top, 20);
    top = linkedStackPush(top, 30);
    top = linkedStackPop(top, &v);
    printf("弹出 %d\n", v);
    return 0;
}
