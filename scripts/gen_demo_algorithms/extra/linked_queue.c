#include <stdio.h>
#include <stdlib.h>

struct Node {
    int data;
    struct Node* next;
};

int linkedQueueEmpty(struct Node* front, struct Node* rear) {
    return front == NULL && rear == NULL;
}

void linkedQueuePush(struct Node** front, struct Node** rear, int x) {
    struct Node* n = (struct Node*)malloc(sizeof(struct Node));
    n->data = x;
    n->next = NULL;
    if (*rear == NULL) {
        *front = n;
        *rear = n;
        return;
    }
    (*rear)->next = n;
    *rear = n;
}

int linkedQueuePop(struct Node** front, struct Node** rear) {
    if (linkedQueueEmpty(*front, *rear)) return -1;
    struct Node* t = *front;
    int v = t->data;
    *front = t->next;
    if (*front == NULL) *rear = NULL;
    free(t);
    return v;
}

int main() {
    struct Node* front = NULL;
    struct Node* rear = NULL;
    linkedQueuePush(&front, &rear, 1);
    linkedQueuePush(&front, &rear, 2);
    linkedQueuePush(&front, &rear, 3);
    printf("%d %d\n", linkedQueuePop(&front, &rear), linkedQueuePop(&front, &rear));
    return 0;
}
