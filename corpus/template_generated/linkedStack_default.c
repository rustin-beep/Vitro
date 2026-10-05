// @category: baseline
#include <stdio.h>
#include <stdlib.h>

struct Node {
    int data;
    struct Node* next;
};

struct Node* push(struct Node* top, int x) {
    struct Node* node = (struct Node*)malloc(sizeof(struct Node));
    node->data = x;
    node->next = top;
    return node;
}

struct Node* pop(struct Node* top) {
    if (top == NULL) return NULL;
    struct Node* temp = top;
    top = top->next;
    free(temp);
    return top;
}

void printStack(struct Node* top) {
    struct Node* p = top;
    while (p != NULL) {
        printf("%d ", p->data);
        p = p->next;
    }
    printf("\n");
}

int main() {
    struct Node* top = NULL;
    top = push(top, 30);
    top = push(top, 20);
    top = push(top, 10);
    printStack(top);
    top = pop(top);
    printStack(top);
    return 0;
}

