#include <stdio.h>
#include <stdlib.h>

struct Node {
    int data;
    struct Node* next;
};

struct Node* deleteNodeList(struct Node* head, int key) {
    struct Node* t = head;
    struct Node* prev = NULL;
    while (t != NULL && t->data != key) {
        prev = t;
        t = t->next;
    }
    if (t == NULL) return head;
    if (prev == NULL) head = t->next;
    else prev->next = t->next;
    free(t);
    return head;
}

int main() {
    struct Node* a = (struct Node*)malloc(sizeof(struct Node));
    struct Node* b = (struct Node*)malloc(sizeof(struct Node));
    struct Node* c = (struct Node*)malloc(sizeof(struct Node));
    a->data = 1;
    b->data = 2;
    c->data = 3;
    a->next = b;
    b->next = c;
    c->next = NULL;
    a = deleteNodeList(a, 2);
    printf("%d\n", a->next->data);
    return 0;
}
